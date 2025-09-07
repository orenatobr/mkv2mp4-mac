# mkv2mp4-mac

A lightweight toolkit for **video conversion and media artwork generation** on **macOS (Apple Silicon)**.

This project provides two main scripts:

1. **`convert_to_mp4_720p.sh`** → Batch converts MKV/MP4 files into MP4 (720p) using hardware-accelerated encoding.
2. **`img_to_boxart.sh`** → Converts raw images into standardized **console boxart covers** for media libraries (Plex, Jellyfin, EmulationStation, etc.).

---

## 🚀 Features

### 🎬 Video Conversion (`convert_to_mp4_720p.sh`)

- **MKV Handling**

  - Keeps **Portuguese (pt/pt-BR)** audio if available, otherwise uses the first audio track.
  - Includes **Portuguese text-based subtitles** (ASS, SSA, SRT, SubRip → converted to `mov_text`).
  - Skips image-based subtitles (PGS).

- **MP4 Handling**

  - Simple re-encode to 720p without track filtering.

- **Encoding Optimizations**

  - Uses `h264_videotoolbox` for **fast Apple Silicon hardware encoding**.
  - Prevents upscaling beyond 1280×720.
  - Normalizes pixel aspect ratio (SAR).

- **Batch Conversion**
  - Processes all `.mkv` and `.mp4` files in a folder.
  - Maintains alphanumeric order (useful for series/episodes).

---

### 🎨 Boxart Generator (`img_to_boxart.sh`)

- Converts any source image into a **standardized boxart cover**.
- Automatically crops, resizes, and adds background padding.
- Preserves aspect ratio while fitting into **2:3 portrait ratio**.
- Generates clean PNG output optimized for media servers.
- Uses **ImageMagick** under the hood.

---

## 📦 Installation

Ensure dependencies are installed:

```bash
brew install ffmpeg imagemagick
```

Clone the repo:

```bash
git clone https://github.com/orenatobr/mkv2mp4-mac.git
cd mkv2mp4-mac
chmod +x convert_to_mp4_720p.sh img_to_boxart.sh
```

---

## 🔧 Usage

### Video Conversion

```bash
./convert_to_mp4_720p.sh "/path/to/input" ["/path/to/output"]
```

Examples:

- Convert MKVs (keeping PT audio/subs):

  ```bash
  ./convert_to_mp4_720p.sh "Bleach" "/Volumes/Renato/Animes/Bleach"
  ```

- Disable hardware decode:

  ```bash
  HWDEC= ./convert_to_mp4_720p.sh "Attack on Titan"
  ```

- Increase video quality:

  ```bash
  VBITS=3000k VMAX=3500k VBUF=7000k ./convert_to_mp4_720p.sh "One Piece"
  ```

---

### Boxart Conversion

```bash
./img_to_boxart.sh input.jpg output.png
```

Examples:

- A file, saving aside of in .png:

  ```bash
  ./img2boxart.sh PS3 "~/Downloads/God of War.jpg"
  ```

- A file, saving with name/dir specifics:

  ```bash
  ./img2boxart.sh PS2 "~/in/Shadow of the Colossus.jpeg" "~/out/SotC.png" --mode crop --bg black
  ```

- Whole folder (recursive), saving to another folder mirroring the structure:

  ```bash
  ./img2boxart.sh PSX "~/covers_raw" "~/covers_png"
  ```

- Batch process multiple cue:

  ```bash
  ./cue2iso_recursive.sh ~/Downloads/
  ```

Resulting images will be properly formatted for Plex/Jellyfin/Emulators.

---

## ⚙️ Configuration

For `convert_to_mp4_720p.sh`, you can adjust encoding settings via environment variables:

| Variable | Default                 | Description                            |
| -------- | ----------------------- | -------------------------------------- |
| `VBITS`  | `2500k`                 | Target video bitrate                   |
| `VMAX`   | `3000k`                 | VBV max rate                           |
| `VBUF`   | `5000k`                 | VBV buffer size                        |
| `ABITS`  | `160k`                  | Audio bitrate                          |
| `HWDEC`  | `-hwaccel videotoolbox` | Hardware decode (set empty to disable) |

---

## 📂 Output

- **Videos:** Saved as `.mp4` in the output directory.
- **Boxart:** Saved as `.png` with a standardized 2:3 ratio.

---

## 📝 License

MIT License – free to use and modify.
