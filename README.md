# mkv2mp4-mac

A lightweight bash script to batch convert video files into **optimized 720p MP4** format on macOS, with support for Apple Silicon (M1/M2) hardware acceleration.

## ✨ Features

- Converts all `.mkv` and `.mp4` files from a source folder to `.mp4` in a target folder.
- Keeps original filenames.
- **MKV mode**: extracts only the **Portuguese audio track** and **Portuguese subtitles** if available.
- **MP4 mode**: just converts the video without worrying about tracks.
- **Hardware acceleration**: uses `h264_videotoolbox` on Apple Silicon for fast encoding.
- Optionally, you can switch to `libx264` (CPU mode) for maximum compression efficiency.

## 🚀 Requirements

- [FFmpeg](https://ffmpeg.org/) (must be installed via [Homebrew](https://brew.sh/) or other method):

```bash
brew install ffmpeg
```

## 🔧 Usage

```bash
./convert_to_mp4_720p.sh <source_folder> <target_folder>
```

Example:

```bash
./convert_to_mp4_720p.sh "Bleach" "/Volumes/Renato/Animes/Bleach720p"
```

This will:

- Scan all `.mkv` and `.mp4` files inside `Bleach/`
- Convert them to `.mp4` in the target folder
- Keep filenames (`BLEACH 01.mkv` → `BLEACH 01.mp4`)

## ⚡ Performance

- By default, the script uses **Apple VideoToolbox** for 4–8× faster encoding.
- If you prefer higher compression and efficiency, change the video codec line to:

```bash
-c:v libx264 -preset slow -crf 21
```

instead of:

```bash
-c:v h264_videotoolbox -b:v 2500k -maxrate 3000k -bufsize 5000k
```

## 📂 Project Structure

```text
.
├── convert_to_mp4_720p.sh   # Main script
├── README.md                # Documentation
```

## 📜 License

MIT License – free to use, modify and share.
