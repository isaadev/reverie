# 〰️ reverie

> slowed · reverb · pitch - an iOS audio editor

reverie is a minimal iOS app that lets you slow down, pitch-shift, and add reverb to any audio file. import from your files or paste a YouTube link to download and edit instantly.

![swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)
![platform](https://img.shields.io/badge/iOS-16%2B-blue?style=flat-square&logo=apple)
![python](https://img.shields.io/badge/Python-3.12-blue?style=flat-square&logo=python)

---

## features

- **speed control** - slow down or speed up audio (0.5× – 1.5×)
- **pitch shifting** - raise or lower pitch independently of speed
- **reverb presets** - small room, medium hall, large hall, chamber, cathedral, plate
- **quick presets** - slowed, dreamy, deep, lofi, nightcore - one tap
- **youtube import** - paste any YouTube URL, audio downloads in the background via our yt-dlp backend
- **export to m4a** - renders the processed audio and saves to your Files
- **lock screen controls** - play/pause and scrubbing from the lock screen and control center
- **typewriter UI** - dark monospaced interface with animated text

---

## project structure

```
reverie/
├── reverie/                  # Xcode iOS project
│   └── reverie/
│       ├── ContentView.swift # entire app (SwiftUI + AVAudioEngine)
│       ├── Info.plist
│       └── Assets.xcassets/
└── ytdl/                     # Python backend for YouTube downloads
    ├── main.py               # FastAPI + yt-dlp endpoint
    ├── requirements.txt
    └── Dockerfile
```

---

## running locally

### ios app

1. Open `reverie/reverie.xcodeproj` in Xcode
2. Select your device or simulator
3. ⌘R to build and run

### youtube download backend

requires Python 3.10+ and [ffmpeg](https://ffmpeg.org/download.html)

```bash
cd ytdl
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8001
```

then update `serviceBase` in `ContentView.swift` to point to the server:

```swift
// local (simulator)
static var serviceBase = "http://localhost:8001"

// on-device - replace with your machine's local IP
static var serviceBase = "http://192.168.x.x:8001"

// deployed
static var serviceBase = "https://your-service.onrender.com"
```

---

## deploying the backend

the `ytdl/` folder includes a `Dockerfile` - deploy anywhere that runs containers:

**render (free tier)**
1. push this repo to GitHub
2. go to [render.com](https://render.com) → New → Web Service
3. point to the `ytdl/` directory
4. set start command: `uvicorn main:app --host 0.0.0.0 --port 8001`
5. copy the deploy URL into `serviceBase` in ContentView.swift

**docker**
```bash
cd ytdl
docker build -t reverie-ytdl .
docker run -p 8001:8001 reverie-ytdl
```

---

## api

| method | endpoint | description |
|--------|----------|-------------|
| `GET` | `/audio?url=<youtube_url>` | download and return audio as M4A |
| `GET` | `/health` | health check |

---

## tech stack

| layer | technology |
|-------|-----------|
| iOS app | SwiftUI, AVAudioEngine, AVAudioUnitTimePitch, AVAudioUnitReverb |
| audio export | AVAssetExportSession (CAF → M4A) |
| lock screen | MPRemoteCommandCenter, MPNowPlayingInfoCenter |
| backend | FastAPI, yt-dlp, ffmpeg |
| container | Docker |

---

## license

MIT
