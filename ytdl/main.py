import os
import uuid
import asyncio
import tempfile
from pathlib import Path

from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import FileResponse
import yt_dlp

app = FastAPI(title="reverie ytdl service")

DOWNLOAD_DIR = Path(tempfile.gettempdir()) / "reverie_ytdl"
DOWNLOAD_DIR.mkdir(exist_ok=True)


def _clean_old_files():
    """Remove files older than 10 minutes to keep disk clean."""
    import time
    now = time.time()
    for f in DOWNLOAD_DIR.glob("*.m4a"):
        if now - f.stat().st_mtime > 600:
            f.unlink(missing_ok=True)


def _download(url: str, out_path: str) -> dict:
    """Blocking yt-dlp call — run in a thread so it doesn't block the event loop."""
    ydl_opts = {
        "format": "bestaudio[ext=m4a]/bestaudio[ext=mp4]/bestaudio",
        "outtmpl": out_path,
        "quiet": True,
        "no_warnings": True,
        # Convert to M4A (AAC) so iOS can play it natively without re-encoding
        "postprocessors": [
            {
                "key": "FFmpegExtractAudio",
                "preferredcodec": "m4a",
                "preferredquality": "128",
            }
        ],
    }
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(url, download=True)
        return {
            "title": info.get("title", "audio"),
            "duration": info.get("duration", 0),
        }


@app.get("/audio")
async def get_audio(url: str = Query(..., description="YouTube URL")):
    """
    Download YouTube audio and return it as an M4A file.
    The file is cleaned up automatically after 10 minutes.
    """
    if not ("youtube.com" in url or "youtu.be" in url):
        raise HTTPException(status_code=400, detail="Only YouTube URLs are supported.")

    _clean_old_files()

    file_id = uuid.uuid4().hex
    out_template = str(DOWNLOAD_DIR / file_id)  # yt-dlp appends the extension

    try:
        loop = asyncio.get_event_loop()
        info = await loop.run_in_executor(None, _download, url, out_template)
    except yt_dlp.utils.DownloadError as e:
        raise HTTPException(status_code=422, detail=f"yt-dlp: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    # yt-dlp may write <id>.m4a after postprocessing
    out_file = Path(out_template + ".m4a")
    if not out_file.exists():
        # fallback: find whatever file was written
        candidates = list(DOWNLOAD_DIR.glob(f"{file_id}*"))
        if not candidates:
            raise HTTPException(status_code=500, detail="Output file not found.")
        out_file = candidates[0]

    safe_title = "".join(c for c in info["title"] if c.isalnum() or c in " _-")[:80]
    return FileResponse(
        path=str(out_file),
        media_type="audio/mp4",
        filename=f"{safe_title}.m4a",
    )


@app.get("/health")
def health():
    return {"status": "ok"}
