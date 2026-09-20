import sharp from "sharp";

/** The app's upload preprocessing (CLAUDE.md): EXIF-upright, long edge ≤ 1568 px, JPEG quality ≈ 0.8. */
export const MAX_LONG_EDGE = 1568;
export const JPEG_QUALITY = 80;

export type PreparedImage = {
  mediaType: "image/jpeg";
  data: string;
  width: number;
  height: number;
  bytes: number;
};

export async function prepareImage(path: string): Promise<PreparedImage> {
  const buffer = await sharp(path)
    .rotate()
    .resize({ width: MAX_LONG_EDGE, height: MAX_LONG_EDGE, fit: "inside", withoutEnlargement: true })
    .jpeg({ quality: JPEG_QUALITY })
    .toBuffer();
  const { width = 0, height = 0 } = await sharp(buffer).metadata();
  return { mediaType: "image/jpeg", data: buffer.toString("base64"), width, height, bytes: buffer.byteLength };
}
