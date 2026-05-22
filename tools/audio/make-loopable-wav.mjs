import fs from "node:fs";
import path from "node:path";

function readWav(filePath) {
  const buf = fs.readFileSync(filePath);
  if (buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE") {
    throw new Error("Not a RIFF/WAVE file");
  }

  let offset = 12;
  let fmt = null;
  let data = null;

  while (offset + 8 <= buf.length) {
    const id = buf.toString("ascii", offset, offset + 4);
    const size = buf.readUInt32LE(offset + 4);
    const start = offset + 8;
    const end = start + size;
    if (end > buf.length) break;

    if (id === "fmt ") {
      const audioFormat = buf.readUInt16LE(start);
      const numChannels = buf.readUInt16LE(start + 2);
      const sampleRate = buf.readUInt32LE(start + 4);
      const byteRate = buf.readUInt32LE(start + 8);
      const blockAlign = buf.readUInt16LE(start + 12);
      const bitsPerSample = buf.readUInt16LE(start + 14);
      fmt = { audioFormat, numChannels, sampleRate, byteRate, blockAlign, bitsPerSample };
    } else if (id === "data") {
      data = buf.subarray(start, end);
    }

    offset = end + (size % 2); // word align
  }

  if (!fmt || !data) throw new Error("Missing fmt/data chunk");
  if (fmt.audioFormat !== 1) throw new Error(`Unsupported WAV format (audioFormat=${fmt.audioFormat})`);
  if (fmt.bitsPerSample !== 16) throw new Error(`Only 16-bit PCM supported (bitsPerSample=${fmt.bitsPerSample})`);

  const samples = new Int16Array(data.buffer, data.byteOffset, Math.floor(data.length / 2));
  const frames = Math.floor(samples.length / fmt.numChannels);
  return { fmt, samples, frames };
}

function writeWav16(filePath, { numChannels, sampleRate, interleaved }) {
  const bytesPerSample = 2;
  const blockAlign = numChannels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;
  const dataSize = interleaved.length * bytesPerSample;

  const headerSize = 44;
  const out = Buffer.allocUnsafe(headerSize + dataSize);

  out.write("RIFF", 0, 4, "ascii");
  out.writeUInt32LE(36 + dataSize, 4);
  out.write("WAVE", 8, 4, "ascii");
  out.write("fmt ", 12, 4, "ascii");
  out.writeUInt32LE(16, 16); // PCM fmt chunk size
  out.writeUInt16LE(1, 20); // audioFormat PCM
  out.writeUInt16LE(numChannels, 22);
  out.writeUInt32LE(sampleRate, 24);
  out.writeUInt32LE(byteRate, 28);
  out.writeUInt16LE(blockAlign, 32);
  out.writeUInt16LE(16, 34); // bitsPerSample
  out.write("data", 36, 4, "ascii");
  out.writeUInt32LE(dataSize, 40);

  for (let i = 0; i < interleaved.length; i++) {
    out.writeInt16LE(interleaved[i], headerSize + i * 2);
  }

  fs.writeFileSync(filePath, out);
}

function toMono(samples, numChannels, frames) {
  const mono = new Float32Array(frames);
  for (let i = 0; i < frames; i++) {
    let acc = 0;
    const base = i * numChannels;
    for (let ch = 0; ch < numChannels; ch++) {
      acc += samples[base + ch] / 32768;
    }
    mono[i] = acc / numChannels;
  }
  return mono;
}

function findTrimPoints(mono, sampleRate) {
  // Conservative trim: removes obvious head/tail silence if present, but won't
  // over-trim constant low-level noise.
  let peak = 0;
  for (let i = 0; i < mono.length; i++) peak = Math.max(peak, Math.abs(mono[i]));
  const threshold = Math.max(0.002, peak * 0.02); // 2% of peak, min floor

  const window = Math.max(1, Math.floor(sampleRate * 0.01)); // 10ms RMS window

  function rmsAt(idx) {
    let sum = 0;
    const end = Math.min(mono.length, idx + window);
    for (let i = idx; i < end; i++) sum += mono[i] * mono[i];
    return Math.sqrt(sum / (end - idx));
  }

  let start = 0;
  for (let i = 0; i < mono.length - window; i += window) {
    if (rmsAt(i) > threshold) {
      start = i;
      break;
    }
  }

  let end = mono.length;
  for (let i = mono.length - window; i > 0; i -= window) {
    if (rmsAt(i) > threshold) {
      end = Math.min(mono.length, i + window);
      break;
    }
  }

  // Keep at least 1s of audio.
  const minLen = Math.floor(sampleRate * 1.0);
  if (end - start < minLen) {
    return { start: 0, end: mono.length };
  }

  return { start, end };
}

function nearestZeroCrossing(mono, idx, radius) {
  const start = Math.max(1, idx - radius);
  const end = Math.min(mono.length - 2, idx + radius);
  let best = idx;
  let bestAbs = Infinity;

  for (let i = start; i <= end; i++) {
    const a = mono[i];
    const b = mono[i + 1];
    if ((a <= 0 && b >= 0) || (a >= 0 && b <= 0)) {
      const score = Math.abs(a) + Math.abs(b);
      if (score < bestAbs) {
        bestAbs = score;
        best = i + 1;
      }
    }
  }
  return best;
}

function findBestLoopEnd(mono, start, end, sampleRate) {
  const trimmedLen = end - start;
  const win = Math.floor(sampleRate * 0.05); // 50ms compare window
  const search = Math.min(Math.floor(sampleRate * 0.8), Math.max(0, trimmedLen - win - 1)); // last 0.8s
  if (search <= 0) return end;

  const startWin = mono.subarray(start, start + win);
  const searchStart = end - win - search;
  let bestIdx = end - win;
  let bestScore = Infinity;

  for (let i = searchStart; i <= end - win; i += 10) {
    let score = 0;
    for (let j = 0; j < win; j++) {
      const d = mono[i + j] - startWin[j];
      score += d * d;
    }
    if (score < bestScore) {
      bestScore = score;
      bestIdx = i;
    }
  }

  // Cut at the start of the best matching window.
  const zeroRadius = Math.floor(sampleRate * 0.01); // 10ms
  return nearestZeroCrossing(mono, bestIdx, zeroRadius);
}

function applyFade(interleaved, numChannels, fadeFrames) {
  const frames = Math.floor(interleaved.length / numChannels);
  const fade = Math.min(fadeFrames, Math.floor(frames / 2));
  if (fade <= 0) return;

  for (let i = 0; i < fade; i++) {
    const t = i / fade;
    const inGain = t;
    const outGain = 1 - t;

    const inBase = i * numChannels;
    const outBase = (frames - 1 - i) * numChannels;
    for (let ch = 0; ch < numChannels; ch++) {
      interleaved[inBase + ch] = Math.round(interleaved[inBase + ch] * inGain);
      interleaved[outBase + ch] = Math.round(interleaved[outBase + ch] * outGain);
    }
  }
}

function sliceInterleaved(samples, numChannels, startFrame, endFrame) {
  const start = startFrame * numChannels;
  const end = endFrame * numChannels;
  return samples.slice(start, end);
}

function main() {
  const input = process.argv[2];
  const output = process.argv[3];
  if (!input || !output) {
    console.error("Usage: node make-loopable-wav.mjs <input.wav> <output.wav>");
    process.exit(2);
  }

  const { fmt, samples, frames } = readWav(input);
  const mono = toMono(samples, fmt.numChannels, frames);

  const { start, end } = findTrimPoints(mono, fmt.sampleRate);
  const startZc = nearestZeroCrossing(mono, start, Math.floor(fmt.sampleRate * 0.02));
  const endCut = findBestLoopEnd(mono, startZc, end, fmt.sampleRate);

  const minFrames = Math.floor(fmt.sampleRate * 1.0);
  const finalEnd = Math.max(endCut, startZc + minFrames);

  const outSamples = sliceInterleaved(samples, fmt.numChannels, startZc, finalEnd);
  applyFade(outSamples, fmt.numChannels, Math.floor(fmt.sampleRate * 0.005)); // 5ms fade

  writeWav16(output, {
    numChannels: fmt.numChannels,
    sampleRate: fmt.sampleRate,
    interleaved: outSamples
  });

  const duration = (outSamples.length / fmt.numChannels) / fmt.sampleRate;
  console.log(
    JSON.stringify(
      {
        input: path.basename(input),
        output: path.basename(output),
        sampleRate: fmt.sampleRate,
        numChannels: fmt.numChannels,
        durationSeconds: Number(duration.toFixed(3)),
        trimStartFrame: startZc,
        trimEndFrame: finalEnd
      },
      null,
      2
    )
  );
}

main();

