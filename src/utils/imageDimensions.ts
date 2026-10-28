export function imageDimensions(data: Buffer): { width: number; height: number } | null {
  if (data.length >= 24 && data.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])) && data.toString('ascii', 12, 16) === 'IHDR') return { width: data.readUInt32BE(16), height: data.readUInt32BE(20) };
  if (data.length >= 30 && data.toString('ascii', 0, 4) === 'RIFF' && data.toString('ascii', 8, 12) === 'WEBP') {
    const kind = data.toString('ascii', 12, 16);
    if (kind === 'VP8X') return { width: 1 + data.readUIntLE(24, 3), height: 1 + data.readUIntLE(27, 3) };
    if (kind === 'VP8 ' && data[23] === 0x9d && data[24] === 1 && data[25] === 0x2a) return { width: data.readUInt16LE(26) & 0x3fff, height: data.readUInt16LE(28) & 0x3fff };
    if (kind === 'VP8L' && data[20] === 0x2f) { const bits = data.readUInt32LE(21); return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 }; }
  }
  if (data.length >= 4 && data[0] === 0xff && data[1] === 0xd8) {
    let i = 2;
    while (i + 4 <= data.length) {
      if (data[i++] !== 0xff) return null;
      while (i < data.length && data[i] === 0xff) i++;
      const marker = data[i++];
      if (marker === 0xd9 || marker === 0xda) break;
      if (marker === 1 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (i + 2 > data.length) return null;
      const length = data.readUInt16BE(i);
      if (length < 2 || i + length > data.length) return null;
      if ([0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker)) {
        if (length < 7) return null;
        return { height: data.readUInt16BE(i + 3), width: data.readUInt16BE(i + 5) };
      }
      i += length;
    }
  }
  return null;
}
