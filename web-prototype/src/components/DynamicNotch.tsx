import React, { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Music, Bell, FolderArchive, ChevronUp, Sparkles, X } from 'lucide-react';
import { Track, NotchNotification, NotchStyle } from '../types/notch';
import { NotchMusicView } from './NotchMusicView';
import { NotchNotificationView } from './NotchNotificationView';
import { NotchDropZone } from './NotchDropZone';
import { AnimatedWaveform } from './AnimatedWaveform';
import { audioEngine } from '../utils/audioEngine';

interface DynamicNotchProps {
  currentTrack: Track;
  isPlaying: boolean;
  currentTime: number;
  playlist: Track[];
  onTogglePlay: () => void;
  onNextTrack: () => void;
  onPrevTrack: () => void;
  onSelectTrack: (track: Track) => void;
  onSeek: (seconds: number) => void;
  activeNotification: NotchNotification | null;
  onDismissNotification: () => void;
  notchStyle?: NotchStyle;
  expandOnHover?: boolean;
}

export const DynamicNotch: React.FC<DynamicNotchProps> = ({
  currentTrack,
  isPlaying,
  currentTime,
  playlist,
  onTogglePlay,
  onNextTrack,
  onPrevTrack,
  onSelectTrack,
  onSeek,
  activeNotification,
  onDismissNotification,
  notchStyle = 'macbook-pro',
  expandOnHover = true,
}) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [activeTab, setActiveTab] = useState<'music' | 'notification' | 'shelf'>('music');
  const notchRef = useRef<HTMLDivElement>(null);

  // If a new notification arrives, auto-open notification tab
  useEffect(() => {
    if (activeNotification) {
      setActiveTab('notification');
      setIsExpanded(true);
    }
  }, [activeNotification]);

  // Click outside to collapse
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (notchRef.current && !notchRef.current.contains(event.target as Node)) {
        if (isExpanded) {
          setIsExpanded(false);
          audioEngine.playHaptic('snap');
        }
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isExpanded]);

  // Handle notch click toggle
  const handleNotchClick = () => {
    if (!isExpanded) {
      setIsExpanded(true);
      audioEngine.playHaptic('expand');
    }
  };

  const handleCollapse = (e: React.MouseEvent) => {
    e.stopPropagation();
    setIsExpanded(false);
    audioEngine.playHaptic('snap');
  };

  // Determine notch dimensions and state
  // Idle: 174px w, 34px h
  // Compact (music playing & not expanded): 250px w, 34px h
  // Expanded: 500px w, auto h
  const isCompactMusic = isPlaying && !isExpanded && !activeNotification;
  const isNotificationActive = Boolean(activeNotification);

  let targetWidth = 174;
  let targetHeight = 34;
  let targetBorderRadius = '0 0 16px 16px';

  if (isExpanded) {
    targetWidth = 510;
    targetHeight = 'auto' as unknown as number;
    targetBorderRadius = '0 0 28px 28px';
  } else if (isNotificationActive) {
    targetWidth = 270;
    targetHeight = 34;
    targetBorderRadius = '0 0 18px 18px';
  } else if (isCompactMusic) {
    targetWidth = 260;
    targetHeight = 34;
    targetBorderRadius = '0 0 18px 18px';
  }

  // Camera privacy LED is active if notification is mic/cam
  const isCameraActive = activeNotification?.type === 'mic_cam';

  return (
    <div className="fixed top-0 left-0 right-0 z-50 flex justify-center pointer-events-none">
      <motion.div
        ref={notchRef}
        layout
        onClick={handleNotchClick}
        onMouseEnter={() => {
          if (expandOnHover && !isExpanded) {
            setIsExpanded(true);
            audioEngine.playHaptic('expand');
          }
        }}
        initial={false}
        animate={{
          width: targetWidth,
          borderRadius: targetBorderRadius,
        }}
        transition={{
          type: 'spring',
          stiffness: 400,
          damping: 30,
          mass: 0.8,
        }}
        className={`pointer-events-auto relative bg-black text-white shadow-2xl overflow-hidden cursor-pointer ${
          isExpanded ? 'p-4 pt-2 shadow-[0_25px_60px_-15px_rgba(0,0,0,0.85)] border-b border-x border-white/[0.08]' : 'hover:brightness-110'
        }`}
        style={{
          boxShadow: isExpanded 
            ? `0 20px 50px -10px ${currentTrack.color}30, 0 10px 30px rgba(0,0,0,0.9)` 
            : '0 4px 15px rgba(0,0,0,0.4)',
        }}
      >
        {/* Physical MacBook Notch Ears (The subtle natural curved blend into the screen top) */}
        {!isExpanded && (
          <>
            <div className="absolute -top-0 -left-2 w-2 h-2 pointer-events-none bg-black" />
            <div className="absolute -top-0 -right-2 w-2 h-2 pointer-events-none bg-black" />
          </>
        )}

        {/* Compact Mode (Idle / Playing / Mini Notification) */}
        {!isExpanded && (
          <div className="w-full h-[34px] flex items-center justify-between px-3 select-none">
            {/* Left flank */}
            <div className="flex items-center min-w-[32px]">
              {isNotificationActive ? (
                <div className="flex items-center space-x-1.5 animate-pulse">
                  <span className="w-2 h-2 rounded-full bg-cyan-400" />
                  <span className="text-[10px] font-medium text-white/90 truncate max-w-[65px]">
                    {activeNotification?.title}
                  </span>
                </div>
              ) : isPlaying ? (
                <div className="flex items-center space-x-1.5 group">
                  <img
                    src={currentTrack.coverUrl}
                    alt={currentTrack.title}
                    className="w-4 h-4 rounded-full object-cover animate-[spin_10s_linear_infinite]"
                  />
                  <span className="text-[10px] font-medium text-white/75 truncate max-w-[65px] hidden sm:inline">
                    {currentTrack.title}
                  </span>
                </div>
              ) : (
                <div className="w-4" />
              )}
            </div>

            {/* Hardware Camera & Sensor Module */}
            <div className="flex items-center space-x-2.5">
              {/* Left Ambient Sensor */}
              <div className="w-1.5 h-1.5 rounded-full bg-neutral-900 border border-neutral-800" />
              
              {/* FaceTime HD Camera Lens */}
              <div className="relative w-3 h-3 rounded-full bg-neutral-950 flex items-center justify-center border border-neutral-800/80 shadow-inner">
                <div className="w-1.5 h-1.5 rounded-full bg-[#0d1624] flex items-center justify-center">
                  <div className="w-0.5 h-0.5 rounded-full bg-blue-400/80" />
                </div>
              </div>

              {/* Privacy Green / Amber Indicator LED */}
              <div 
                className={`w-1.5 h-1.5 rounded-full transition-all duration-300 ${
                  isCameraActive 
                    ? 'bg-emerald-400 shadow-[0_0_8px_#34d399] animate-pulse' 
                    : 'bg-neutral-900'
                }`} 
              />
            </div>

            {/* Right flank */}
            <div className="flex items-center justify-end min-w-[32px]">
              {isNotificationActive ? (
                <span className="text-[9px] font-mono text-cyan-400 font-semibold">
                  NUEVO
                </span>
              ) : isPlaying ? (
                <AnimatedWaveform isPlaying={isPlaying} color={currentTrack.color} barCount={4} height={11} size="mini" />
              ) : (
                <div className="w-4" />
              )}
            </div>
          </div>
        )}

        {/* Expanded Island View */}
        <AnimatePresence>
          {isExpanded && (
            <motion.div
              initial={{ opacity: 0, y: -8 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -6 }}
              transition={{ duration: 0.2 }}
              className="w-full pt-1"
            >
              {/* Top notch navigation bar */}
              <div className="flex items-center justify-between pb-2 mb-3 border-b border-white/[0.08]">
                {/* Mode Tabs */}
                <div className="flex items-center space-x-1 bg-white/5 p-0.5 rounded-xl">
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setActiveTab('music');
                      audioEngine.playHaptic('click');
                    }}
                    className={`flex items-center space-x-1 px-3 py-1 rounded-lg text-xs font-medium transition ${
                      activeTab === 'music'
                        ? 'bg-white/20 text-white shadow-sm'
                        : 'text-white/50 hover:text-white'
                    }`}
                  >
                    <Music className="w-3.5 h-3.5" />
                    <span>Música</span>
                  </button>

                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setActiveTab('notification');
                      audioEngine.playHaptic('click');
                    }}
                    className={`relative flex items-center space-x-1 px-3 py-1 rounded-lg text-xs font-medium transition ${
                      activeTab === 'notification'
                        ? 'bg-white/20 text-white shadow-sm'
                        : 'text-white/50 hover:text-white'
                    }`}
                  >
                    <Bell className="w-3.5 h-3.5" />
                    <span>Notificaciones</span>
                    {activeNotification && (
                      <span className="w-1.5 h-1.5 rounded-full bg-cyan-400 animate-pulse" />
                    )}
                  </button>

                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setActiveTab('shelf');
                      audioEngine.playHaptic('click');
                    }}
                    className={`flex items-center space-x-1 px-3 py-1 rounded-lg text-xs font-medium transition ${
                      activeTab === 'shelf'
                        ? 'bg-white/20 text-white shadow-sm'
                        : 'text-white/50 hover:text-white'
                    }`}
                  >
                    <FolderArchive className="w-3.5 h-3.5" />
                    <span>Shelf</span>
                  </button>
                </div>

                {/* Hardware camera indicator in expanded mode */}
                <div className="flex items-center space-x-1.5 px-2 py-0.5 rounded-full bg-white/5">
                  <div className="w-2 h-2 rounded-full bg-neutral-900 border border-neutral-700 flex items-center justify-center">
                    <div className="w-0.5 h-0.5 rounded-full bg-blue-400" />
                  </div>
                  <span className="text-[10px] text-white/40">FaceTime HD</span>
                </div>

                {/* Collapse button */}
                <button
                  onClick={handleCollapse}
                  className="p-1 rounded-lg hover:bg-white/10 text-white/50 hover:text-white transition"
                  title="Plegar Notch"
                >
                  <ChevronUp className="w-4 h-4" />
                </button>
              </div>

              {/* Tab Content Panels */}
              <div className="py-1">
                {activeTab === 'music' && (
                  <NotchMusicView
                    currentTrack={currentTrack}
                    isPlaying={isPlaying}
                    currentTime={currentTime}
                    playlist={playlist}
                    onTogglePlay={onTogglePlay}
                    onNextTrack={onNextTrack}
                    onPrevTrack={onPrevTrack}
                    onSelectTrack={onSelectTrack}
                    onSeek={onSeek}
                  />
                )}

                {activeTab === 'notification' && (
                  <div>
                    {activeNotification ? (
                      <NotchNotificationView
                        notification={activeNotification}
                        onDismiss={() => {
                          onDismissNotification();
                          setActiveTab('music');
                        }}
                      />
                    ) : (
                      <div className="text-center py-6 text-white/50">
                        <Bell className="w-8 h-8 mx-auto mb-2 opacity-30" />
                        <p className="text-xs font-medium text-white/70">Sin notificaciones activas</p>
                        <p className="text-[11px] text-white/40 mt-0.5">
                          Usa los botones del panel inferior para simular AirDrop, MagSafe o Temporizador.
                        </p>
                      </div>
                    )}
                  </div>
                )}

                {activeTab === 'shelf' && <NotchDropZone />}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </motion.div>
    </div>
  );
};
