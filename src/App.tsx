/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect } from 'react';
import { MacMenuBar } from './components/MacMenuBar';
import { DynamicNotch } from './components/DynamicNotch';
import { MacDesktop } from './components/MacDesktop';
import { SimulatorControls } from './components/SimulatorControls';
import { PLAYLIST_PRESETS, NOTIFICATION_PRESETS, WALLPAPER_PRESETS } from './utils/mockData';
import { Track, NotchNotification } from './types/notch';
import { audioEngine } from './utils/audioEngine';

export default function App() {
  const [playlist] = useState<Track[]>(PLAYLIST_PRESETS);
  const [currentTrackIndex, setCurrentTrackIndex] = useState(0);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(14);
  const [activeNotification, setActiveNotification] = useState<NotchNotification | null>(() => {
    // Start with a gentle MagSafe or AirDrop preview so the user immediately discovers the notch capability!
    return NOTIFICATION_PRESETS[0]; // AirDrop
  });
  const [selectedWallpaper, setSelectedWallpaper] = useState(WALLPAPER_PRESETS[0].url);
  const [expandOnHover, setExpandOnHover] = useState(true);
  const [soundEffects, setSoundEffects] = useState(true);
  const [isRealNotchMode, setIsRealNotchMode] = useState(false);

  const currentTrack = playlist[currentTrackIndex] || playlist[0];

  // Sync with audio engine
  useEffect(() => {
    audioEngine.onTick((time, playing) => {
      setCurrentTime(time);
      setIsPlaying(playing);
    });
  }, []);

  // Keyboard shortcut support
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return;
      }
      if (e.code === 'Space') {
        e.preventDefault();
        handleTogglePlay();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isPlaying, currentTrackIndex]);

  const handleTogglePlay = () => {
    const nextPlaying = audioEngine.togglePlay(currentTrack.id);
    setIsPlaying(nextPlaying);
  };

  const handleNextTrack = () => {
    const nextIdx = (currentTrackIndex + 1) % playlist.length;
    setCurrentTrackIndex(nextIdx);
    audioEngine.seek(0);
    if (isPlaying) {
      audioEngine.play(playlist[nextIdx].id);
    }
  };

  const handlePrevTrack = () => {
    const prevIdx = (currentTrackIndex - 1 + playlist.length) % playlist.length;
    setCurrentTrackIndex(prevIdx);
    audioEngine.seek(0);
    if (isPlaying) {
      audioEngine.play(playlist[prevIdx].id);
    }
  };

  const handleSelectTrack = (track: Track) => {
    const idx = playlist.findIndex((t) => t.id === track.id);
    if (idx !== -1) {
      setCurrentTrackIndex(idx);
      audioEngine.seek(0);
      if (isPlaying) {
        audioEngine.play(track.id);
      }
    }
  };

  const handleSeek = (seconds: number) => {
    audioEngine.seek(seconds);
    setCurrentTime(seconds);
  };

  const handleTriggerNotification = (notif: NotchNotification) => {
    setActiveNotification({
      ...notif,
      timestamp: Date.now(),
    });
  };

  const handleDismissNotification = () => {
    setActiveNotification(null);
  };

  const handleToggleSoundEffects = () => {
    const next = !soundEffects;
    setSoundEffects(next);
    audioEngine.setSoundEffects(next);
  };

  return (
    <div className={`relative w-screen h-screen overflow-hidden font-sans select-none ${isRealNotchMode ? 'bg-transparent' : 'bg-black'}`}>
      {/* Dynamic Desktop Wallpaper Background (hidden in Real Notch Mode) */}
      {!isRealNotchMode && (
        <div
          className="absolute inset-0 bg-cover bg-center transition-all duration-700 ease-in-out"
          style={{
            backgroundImage: `url(${selectedWallpaper})`,
          }}
        >
          <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-transparent to-black/60 pointer-events-none" />
        </div>
      )}

      {/* Realistic macOS Menu Bar (hidden in Real Notch Mode) */}
      {!isRealNotchMode && (
        <MacMenuBar
          appName={isPlaying ? 'Música' : 'Finder'}
          isAudioPlaying={isPlaying}
          batteryLevel={88}
          isCharging={activeNotification?.type === 'magsafe'}
        />
      )}

      {/* The Dynamic Notch for Mac (Master Centerpiece) */}
      <DynamicNotch
        currentTrack={currentTrack}
        isPlaying={isPlaying}
        currentTime={currentTime}
        playlist={playlist}
        onTogglePlay={handleTogglePlay}
        onNextTrack={handleNextTrack}
        onPrevTrack={handlePrevTrack}
        onSelectTrack={handleSelectTrack}
        onSeek={handleSeek}
        activeNotification={activeNotification}
        onDismissNotification={handleDismissNotification}
        expandOnHover={expandOnHover}
      />

      {/* macOS Desktop Workspace (Folders, Dock, Instructions) */}
      {!isRealNotchMode && (
        <MacDesktop
          currentTrack={currentTrack}
          isPlaying={isPlaying}
          onOpenNotchManual={() => {
            if (!activeNotification) {
              setActiveNotification(NOTIFICATION_PRESETS[1]); // MagSafe
            }
          }}
        />
      )}

      {/* Testing & Simulator Controls Dock */}
      <SimulatorControls
        currentTrack={currentTrack}
        isPlaying={isPlaying}
        onTogglePlay={handleTogglePlay}
        onNextTrack={handleNextTrack}
        onTriggerNotification={handleTriggerNotification}
        onClearNotification={handleDismissNotification}
        hasActiveNotification={Boolean(activeNotification)}
        selectedWallpaper={selectedWallpaper}
        onSelectWallpaper={setSelectedWallpaper}
        expandOnHover={expandOnHover}
        onToggleExpandOnHover={() => setExpandOnHover((v) => !v)}
        soundEffects={soundEffects}
        onToggleSoundEffects={handleToggleSoundEffects}
        isRealNotchMode={isRealNotchMode}
        onToggleRealNotchMode={() => setIsRealNotchMode((v) => !v)}
      />
    </div>
  );
}
