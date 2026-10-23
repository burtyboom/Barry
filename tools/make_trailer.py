"""Cut the trailer together from the Movie Maker recording.

    python tools/make_trailer.py trailer

Reads <dir>/raw.avi (Godot --write-movie output) and <dir>/cuts.json (frame ranges the
director script kept), joins the kept clips, mixes the game sound effects under the
game's own music (<dir>/music.wav) and writes <dir>/Island4WD_trailer.mp4 (1280x720, H.264).
Needs ffmpeg: uses the one from the imageio-ffmpeg pip package if it isn't on PATH.
"""
import json
import os
import shutil
import subprocess
import sys


def ffmpeg_exe() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def main() -> None:
    d = sys.argv[1] if len(sys.argv) > 1 else "trailer"
    meta = json.load(open(os.path.join(d, "cuts.json")))
    fps = float(meta["fps"])
    cuts = meta["cuts"]
    raw = os.path.join(d, "raw.avi")
    music = os.path.join(d, "music.wav")
    out = os.path.join(d, "Island4WD_trailer.mp4")
    parts = []
    total = 0.0
    for i, (a, b) in enumerate(cuts):
        s, e = a / fps, b / fps
        total += e - s
        parts.append(f"[0:v]trim=start={s:.4f}:end={e:.4f},setpts=PTS-STARTPTS[v{i}];"
                     f"[0:a]atrim=start={s:.4f}:end={e:.4f},asetpts=PTS-STARTPTS[a{i}];")
    n = len(cuts)
    joined = "".join(f"[v{i}][a{i}]" for i in range(n))
    fade_out = max(total - 1.5, 0)
    fc = "".join(parts) + f"{joined}concat=n={n}:v=1:a=1[vc][ac];"
    fc += f"[vc]fade=t=in:st=0:d=0.6,fade=t=out:st={fade_out:.2f}:d=1.5[v];"
    inputs = ["-i", raw]
    if os.path.exists(music):
        inputs += ["-stream_loop", "-1", "-i", music]
        fc += (f"[ac]volume=0.55[sfx];[1:a]atrim=0:{total:.2f},volume=1.0,"
               f"afade=t=in:st=0:d=0.8,afade=t=out:st={fade_out:.2f}:d=1.5[mus];"
               f"[sfx][mus]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]")
    else:
        fc += "[ac]anull[a]"
    cmd = [ffmpeg_exe(), "-y", *inputs, "-filter_complex", fc, "-map", "[v]", "-map", "[a]",
           "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(int(fps)),
           "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", out]
    print(f"{n} clips, {total:.1f} s")
    subprocess.run(cmd, check=True)
    print("wrote", os.path.abspath(out))


if __name__ == "__main__":
    main()
