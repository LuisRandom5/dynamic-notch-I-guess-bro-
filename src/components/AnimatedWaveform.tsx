import React, { useEffect, useState } from 'react';
import { audioEngine } from '../utils/audioEngine';

interface AnimatedWaveformProps {
  isPlaying: boolean;
  color?: string;
  barCount?: number;
  height?: number;
  size?: 'mini' | 'normal' | 'large';
}

export const AnimatedWaveform: React.FC<AnimatedWaveformProps> = ({
  isPlaying,
  color = '#22c55e', // Apple green / dynamic
  barCount = 4,
  height = 14,
  size = 'mini',
}) => {
  const [levels, setLevels] = useState<number[]>(() => new Array(barCount).fill(0.3));

  useEffect(() => {
    let animationFrameId: number;

    const updateWaveform = () => {
      if (isPlaying) {
        const freqData = audioEngine.getFrequencyData();
        const newLevels = Array.from({ length: barCount }, (_, i) => {
          if (freqData && freqData.length > 0) {
            const index = Math.floor((i / barCount) * (freqData.length / 2));
            const val = (freqData[index] || 60) / 255;
            // Add subtle random variance for lively Apple-like bounce
            return Math.max(0.2, Math.min(1, val * 1.2 + Math.random() * 0.15));
          }
          return 0.3 + Math.random() * 0.6;
        });
        setLevels(newLevels);
      } else {
        setLevels(new Array(barCount).fill(0.15));
      }
      animationFrameId = requestAnimationFrame(updateWaveform);
    };

    animationFrameId = requestAnimationFrame(updateWaveform);
    return () => cancelAnimationFrame(animationFrameId);
  }, [isPlaying, barCount]);

  const barWidth = size === 'mini' ? 'w-[2.5px]' : size === 'large' ? 'w-[4px]' : 'w-[3px]';
  const gap = size === 'mini' ? 'gap-[2px]' : 'gap-[3px]';

  return (
    <div
      className={`flex items-center justify-center ${gap}`}
      style={{ height: `${height}px` }}
      aria-label="Audio equalizer"
    >
      {levels.map((lvl, index) => (
        <span
          key={index}
          className={`${barWidth} rounded-full transition-all duration-100 ease-out`}
          style={{
            backgroundColor: color,
            height: isPlaying ? `${Math.max(3, lvl * height)}px` : '3px',
            opacity: isPlaying ? 0.95 : 0.4,
          }}
        />
      ))}
    </div>
  );
};
