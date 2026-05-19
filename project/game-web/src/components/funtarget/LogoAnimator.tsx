"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import styles from "./LogoAnimator.module.css";

const FRAME_INTERVAL_MS = 90;

export type LogoAnimatorProps = {
  spinning: boolean;
  resetToken: number;
};

export function LogoAnimator({ spinning, resetToken }: LogoAnimatorProps) {
  const frameUrls = useMemo(() => {
    const base = "/funTargrtAsset/media/BAD/golo";
    return Array.from({ length: 20 }, (_, idx) => `${base}/Logo${idx}.jpg`);
  }, []);

  const [frameUrl, setFrameUrl] = useState<string>(frameUrls[0] ?? "");
  const frameIndexRef = useRef<number>(0);

  useEffect(() => {
    frameIndexRef.current = 0;
    setFrameUrl(frameUrls[0] ?? "");
  }, [frameUrls, resetToken]);

  useEffect(() => {
    if (!spinning) return;

    frameIndexRef.current = 0;
    setFrameUrl(frameUrls[0] ?? "");

    const timer = window.setInterval(() => {
      frameIndexRef.current = (frameIndexRef.current + 1) % frameUrls.length;
      setFrameUrl(frameUrls[frameIndexRef.current] ?? frameUrls[0] ?? "");
    }, FRAME_INTERVAL_MS);

    return () => {
      window.clearInterval(timer);
    };
  }, [frameUrls, spinning]);

  return (
    <div className={styles.host}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img className={styles.centerBall} src={frameUrl} alt="Center" />
    </div>
  );
}

