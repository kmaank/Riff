
import os
import subprocess
import sys
from PIL import Image, ImageOps

def generate_icons(source_path, output_dir):
    if not os.path.exists(source_path):
        print(f"Error: Source image not found at {source_path}")
        sys.exit(1)

    # Load Source
    img = Image.open(source_path)
    if img.mode != 'RGBA':
        img = img.convert('RGBA')

    # Tray Icon Size
    # macOS Menu Bar standard is often 22pt. Retina is 44px.
    # Let's generate 44x44 and let macOS scale down if needed (or pystray handles it).
    # Pystray often likes specific sizes.
    tray_size = (22, 22)  # Point size
    tray_img = img.resize(tray_size, Image.Resampling.LANCZOS)
    
    # Save Idle
    tray_img.save(os.path.join(output_dir, "tray_idle.png"))
    print(f"Saved assets/tray_idle.png")
    
    # Helper to tint
    def tint_image(src, color):
        # Create a solid color image
        colored = Image.new("RGBA", src.size, color)
        # Use the source alpha channel as a mask
        dst = Image.composite(colored, src, src)
        return dst

    # Save Recording (Red)
    # Color: Red #FF3B30 (macOS system red-ish) -> (255, 59, 48)
    tray_rec = tint_image(tray_img, (255, 59, 48, 255))
    tray_rec.save(os.path.join(output_dir, "tray_recording.png"))
    print(f"Saved assets/tray_recording.png")
    
    # Save Processing (Yellow/Orange)
    # Color: Orange #FF9500 (macOS system orange) -> (255, 149, 0)
    tray_proc = tint_image(tray_img, (255, 149, 0, 255))
    tray_proc.save(os.path.join(output_dir, "tray_processing.png"))
    print(f"Saved assets/tray_processing.png")

if __name__ == "__main__":
    # Using the larger image as source
    source = "/Users/mayankkamal/.gemini/antigravity/brain/f710e139-6e3f-4551-b101-73c9723178f8/uploaded_image_1_1768759579831.png"
    output = "/Users/mayankkamal/Documents/Echoflow/assets"
    generate_icons(source, output)
