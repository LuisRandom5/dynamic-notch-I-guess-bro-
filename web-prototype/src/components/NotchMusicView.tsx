import React, { useState } from 'react';
import { 
  Play, 
  SkipBack, 
  SkipForward, 
  Volume2, 
  VolumeX, 
  Shuffle, 
  Repeat, 
  Headphones, 
  ListMusic 
} from 'lucide-react';
import { motion, AnimatePresence, useReducedMotion } from 'motion/react';
import { Track } from '../types/notch';
import { AnimatedWaveform } from './AnimatedWaveform';
import { audioEngine } from '../utils/audioEngine';

interface NotchMusicViewProps {
  currentTrack: Track;
  isPlaying: boolean;
  currentTime: number;
  playlist: Track[];
  onTogglePlay: () => void;
  onNextTrack: () => void;
  onPrevTrack: () => void;
  onSelectTrack: (track: Track) => void;
  onSeek: (seconds: number) => void;
}

export const NotchMusicView: React.FC<NotchMusicViewProps> = ({
  currentTrack,
  isPlaying,
  currentTime,
  playlist,
  onTogglePlay,
  onNextTrack,
  onPrevTrack,
  onSelectTrack,
  onSeek,
}) => {
  const [volume, setVolume] = useState(audioEngine.getVolume());
  const [isMuted, setIsMuted] = useState(false);
  const [isShuffle, setIsShuffle] = useState(false);
  const [isRepeat, setIsRepeat] = useState(false);
  const [showPlaylist, setShowPlaylist] = useState(false);
  const [outputDevice, setOutputDevice] = useState<'airpods' | 'macbook'>('airpods');
  
  // Seguimiento de dirección para la animación coordinada de Apple Music (1 = siguiente, -1 = anterior)
  const [direction, setDirection] = useState<1 | -1>(1);

  // Detección de accesibilidad: Reducir movimiento del sistema
  const prefersReducedMotion = useReducedMotion();

  const formatTime = (secs: number) => {
    const m = Math.floor(secs / 60);
    const s = Math.floor(secs % 60);
    return `${m}:${s < 10 ? '0' : ''}${s}`;
  };

  const handleVolumeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseFloat(e.target.value);
    setVolume(val);
    setIsMuted(val === 0);
    audioEngine.setVolume(val);
  };

  const toggleMute = () => {
    if (isMuted) {
      setIsMuted(false);
      audioEngine.setVolume(volume > 0 ? volume : 0.5);
    } else {
      setIsMuted(true);
      audioEngine.setVolume(0);
    }
    audioEngine.playHaptic('click');
  };

  const handleScrubberChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const val = parseFloat(e.target.value);
    onSeek(val);
  };

  // Handlers con ejecución inmediata y dirección de transición
  const handleNext = () => {
    setDirection(1);
    audioEngine.playHaptic('click');
    onNextTrack();
  };

  const handlePrev = () => {
    setDirection(-1);
    audioEngine.playHaptic('click');
    onPrevTrack();
  };

  const handleSelect = (track: Track) => {
    const currentIndex = playlist.findIndex((t) => t.id === currentTrack.id);
    const targetIndex = playlist.findIndex((t) => t.id === track.id);
    setDirection(targetIndex >= currentIndex ? 1 : -1);
    onSelectTrack(track);
    setShowPlaylist(false);
  };

  const handleToggle = () => {
    audioEngine.playHaptic('snap');
    onTogglePlay();
  };

  // Variantes de animación de carátula 3D tipo tarjeta física (Apple Music)
  const artworkVariants = {
    enter: (dir: number) => ({
      x: prefersReducedMotion ? 0 : dir > 0 ? 54 : -54,
      rotateY: prefersReducedMotion ? 0 : dir > 0 ? 38 : -38,
      scale: prefersReducedMotion ? 1 : 0.88,
      opacity: 0,
    }),
    center: {
      x: 0,
      rotateY: 0,
      scale: 1,
      opacity: 1,
      transition: prefersReducedMotion
        ? { duration: 0.12, ease: 'easeOut' as const }
        : {
            x: { type: 'spring' as const, stiffness: 420, damping: 28, mass: 0.65 },
            rotateY: { type: 'spring' as const, stiffness: 420, damping: 28, mass: 0.65 },
            scale: { type: 'spring' as const, stiffness: 420, damping: 28, mass: 0.65 },
            opacity: { duration: 0.18, ease: 'easeOut' as const },
          },
    },
    exit: (dir: number) => ({
      x: prefersReducedMotion ? 0 : dir > 0 ? -54 : 54,
      rotateY: prefersReducedMotion ? 0 : dir > 0 ? -38 : 38,
      scale: prefersReducedMotion ? 1 : 0.88,
      opacity: 0,
      transition: prefersReducedMotion
        ? { duration: 0.12, ease: 'easeIn' as const }
        : {
            x: { type: 'spring' as const, stiffness: 420, damping: 28, mass: 0.65 },
            rotateY: { type: 'spring' as const, stiffness: 420, damping: 28, mass: 0.65 },
            scale: { type: 'spring' as const, stiffness: 420, damping: 28, mass: 0.65 },
            opacity: { duration: 0.16, ease: 'easeIn' as const },
          },
    }),
  };

  // Variantes para la información de texto (título y artista)
  const textVariants = {
    enter: (dir: number) => ({
      x: prefersReducedMotion ? 0 : dir > 0 ? 14 : -14,
      opacity: 0,
    }),
    center: {
      x: 0,
      opacity: 1,
      transition: {
        duration: 0.22,
        ease: [0.16, 1, 0.3, 1] as const,
      },
    },
    exit: (dir: number) => ({
      x: prefersReducedMotion ? 0 : dir > 0 ? -14 : 14,
      opacity: 0,
      transition: {
        duration: 0.16,
        ease: [0.16, 1, 0.3, 1] as const,
      },
    }),
  };

  return (
    <div className="w-full text-white select-none">
      {/* Top bar with output device and equalizer */}
      <div className="flex items-center justify-between text-xs text-white/50 mb-3 px-1">
        <button
          onClick={() => {
            setOutputDevice((d) => (d === 'airpods' ? 'macbook' : 'airpods'));
            audioEngine.playHaptic('click');
          }}
          className="flex items-center space-x-1.5 hover:text-white transition px-2 py-0.5 rounded-full bg-white/5 hover:bg-white/10"
        >
          <Headphones className="w-3 h-3 text-cyan-400" />
          <span className="text-[11px] font-medium text-white/80">
            {outputDevice === 'airpods' ? 'AirPods Pro de Carlos (Audio Espacial)' : 'Altavoces MacBook Pro'}
          </span>
        </button>

        <div className="flex items-center space-x-2">
          <AnimatedWaveform isPlaying={isPlaying} color={currentTrack.color} barCount={5} height={12} size="mini" />
          <button
            onClick={() => {
              setShowPlaylist((p) => !p);
              audioEngine.playHaptic('snap');
            }}
            className={`p-1 rounded-full transition ${showPlaylist ? 'bg-white/20 text-white' : 'hover:bg-white/10 text-white/60'}`}
            title="Ver Lista de Reproducción"
          >
            <ListMusic className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {showPlaylist ? (
        /* Playlist Switcher View */
        <div className="space-y-1.5 max-h-[160px] overflow-y-auto pr-1 mb-2 custom-scrollbar">
          {playlist.map((track) => {
            const isCurrent = track.id === currentTrack.id;
            return (
              <button
                key={track.id}
                onClick={() => handleSelect(track)}
                className={`w-full flex items-center justify-between p-2 rounded-xl text-left transition ${
                  isCurrent ? 'bg-white/15 text-white' : 'hover:bg-white/5 text-white/70'
                }`}
              >
                <div className="flex items-center space-x-3 min-w-0">
                  <img
                    src={track.coverUrl}
                    alt={track.title}
                    className="w-8 h-8 rounded-lg object-cover shadow-sm"
                  />
                  <div className="min-w-0">
                    <p className="text-xs font-medium truncate text-white">{track.title}</p>
                    <p className="text-[11px] text-white/50 truncate">{track.artist}</p>
                  </div>
                </div>
                {isCurrent && (
                  <AnimatedWaveform isPlaying={isPlaying} color={track.color} barCount={4} height={10} size="mini" />
                )}
              </button>
            );
          })}
        </div>
      ) : (
        /* Main Music Player View */
        <div className="flex items-center space-x-4 mb-3">
          {/* Album Artwork con perspectiva 3D realista y rotación sobre eje Y */}
          <div className="relative flex-shrink-0">
            <div
              className="w-16 h-16 sm:w-20 sm:h-20 rounded-2xl overflow-hidden relative border border-white/10 transition-shadow duration-300"
              style={{
                perspective: 800,
                transformStyle: 'preserve-3d',
                boxShadow: `0 10px 30px -5px ${currentTrack.color}50`,
              }}
            >
              <AnimatePresence mode="popLayout" custom={direction} initial={false}>
                <motion.div
                  key={currentTrack.id}
                  custom={direction}
                  variants={artworkVariants}
                  initial="enter"
                  animate="center"
                  exit="exit"
                  className="absolute inset-0 w-full h-full"
                >
                  <img
                    src={currentTrack.coverUrl}
                    alt={currentTrack.title}
                    className={`w-full h-full object-cover transition-[filter] duration-300 ${
                      isPlaying ? 'brightness-105' : 'brightness-90'
                    }`}
                  />
                </motion.div>
              </AnimatePresence>

              {/* Reflejo vinilo sutil fijo sin recalcular filtros */}
              <div className="absolute inset-0 bg-gradient-to-tr from-black/40 via-transparent to-white/10 pointer-events-none" />
            </div>

            {isPlaying && (
              <span 
                className="absolute -bottom-1 -right-1 w-3.5 h-3.5 rounded-full border-2 border-black flex items-center justify-center animate-pulse z-10"
                style={{ backgroundColor: currentTrack.color }}
              />
            )}
          </div>

          {/* Track Info con transición coordinada suave */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center space-x-2">
              <span className="text-[10px] uppercase tracking-wider font-semibold px-1.5 py-0.5 rounded bg-white/10 text-white/70">
                {currentTrack.genre}
              </span>
            </div>

            <div className="overflow-hidden min-h-[44px]">
              <AnimatePresence mode="popLayout" custom={direction} initial={false}>
                <motion.div
                  key={currentTrack.id}
                  custom={direction}
                  variants={textVariants}
                  initial="enter"
                  animate="center"
                  exit="exit"
                >
                  <h4 className="text-base font-semibold tracking-tight text-white truncate mt-0.5">
                    {currentTrack.title}
                  </h4>
                  <p className="text-xs text-white/60 truncate font-normal">
                    {currentTrack.artist} · <span className="text-white/40">{currentTrack.album}</span>
                  </p>
                </motion.div>
              </AnimatePresence>
            </div>

            {/* Interactive Timeline Scrubber */}
            <div className="mt-2">
              <div className="relative flex items-center group">
                <input
                  type="range"
                  min="0"
                  max={currentTrack.duration}
                  step="0.5"
                  value={currentTime}
                  onChange={handleScrubberChange}
                  className="w-full h-1.5 bg-white/15 rounded-lg appearance-none cursor-pointer accent-white hover:h-2 transition-all focus:outline-none"
                  style={{
                    background: `linear-gradient(to right, ${currentTrack.color} ${(currentTime / currentTrack.duration) * 100}%, rgba(255,255,255,0.15) ${(currentTime / currentTrack.duration) * 100}%)`,
                  }}
                />
              </div>
              <div className="flex justify-between text-[10px] text-white/40 tabular-nums font-mono mt-1">
                <span>{formatTime(currentTime)}</span>
                <span>-{formatTime(Math.max(0, currentTrack.duration - currentTime))}</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Playback Controls & Volume Row */}
      <div className="flex items-center justify-between pt-2 border-t border-white/[0.08]">
        {/* Secondary options: Shuffle & Repeat */}
        <div className="flex items-center space-x-1">
          <button
            onClick={() => {
              setIsShuffle(!isShuffle);
              audioEngine.playHaptic('click');
            }}
            className={`p-1.5 rounded-lg transition ${isShuffle ? 'text-cyan-400 bg-white/10' : 'text-white/40 hover:text-white/80'}`}
            title="Aleatorio"
          >
            <Shuffle className="w-3.5 h-3.5" />
          </button>
          <button
            onClick={() => {
              setIsRepeat(!isRepeat);
              audioEngine.playHaptic('click');
            }}
            className={`p-1.5 rounded-lg transition ${isRepeat ? 'text-cyan-400 bg-white/10' : 'text-white/40 hover:text-white/80'}`}
            title="Repetir"
          >
            <Repeat className="w-3.5 h-3.5" />
          </button>
        </div>

        {/* Center Primary Controls con microanimaciones nativas de Apple Music */}
        <div className="flex items-center space-x-3">
          {/* Botón Pista Anterior */}
          <motion.button
            whileTap={{ scale: prefersReducedMotion ? 1 : 0.88 }}
            whileHover={{ scale: prefersReducedMotion ? 1 : 1.05 }}
            transition={{
              type: 'spring',
              stiffness: 550,
              damping: 24,
              mass: 0.5,
            }}
            onClick={handlePrev}
            className="w-8 h-8 flex items-center justify-center rounded-full text-white/70 hover:text-white hover:bg-white/10 active:bg-white/15 transition-colors focus:outline-none"
            title="Anterior"
          >
            <SkipBack className="w-4 h-4 fill-current" />
          </motion.button>

          {/* Botón Play/Pause con microanimación vectorial coordinada (SF Symbols style) */}
          <motion.button
            whileTap={{ scale: prefersReducedMotion ? 1 : 0.88 }}
            whileHover={{ scale: prefersReducedMotion ? 1 : 1.05 }}
            transition={{
              type: 'spring',
              stiffness: 520,
              damping: 24,
              mass: 0.5,
            }}
            onClick={handleToggle}
            className="w-9 h-9 rounded-full bg-white text-black flex items-center justify-center shadow-lg shadow-white/20 select-none focus:outline-none"
            title={isPlaying ? 'Pausar' : 'Reproducir'}
          >
            <div className="relative w-4 h-4 flex items-center justify-center overflow-hidden">
              <AnimatePresence mode="wait" initial={false}>
                {isPlaying ? (
                  <motion.div
                    key="pause-icon"
                    initial={{
                      scale: prefersReducedMotion ? 1 : 0.70,
                      opacity: 0,
                      rotate: prefersReducedMotion ? 0 : -25,
                    }}
                    animate={{ scale: 1, opacity: 1, rotate: 0 }}
                    exit={{
                      scale: prefersReducedMotion ? 1 : 0.70,
                      opacity: 0,
                      rotate: prefersReducedMotion ? 0 : 25,
                    }}
                    transition={{
                      duration: 0.18,
                      ease: [0.16, 1, 0.3, 1],
                    }}
                    className="flex items-center space-x-1"
                  >
                    <span className="w-1.5 h-3.5 bg-black rounded-full" />
                    <span className="w-1.5 h-3.5 bg-black rounded-full" />
                  </motion.div>
                ) : (
                  <motion.div
                    key="play-icon"
                    initial={{
                      scale: prefersReducedMotion ? 1 : 0.70,
                      opacity: 0,
                      rotate: prefersReducedMotion ? 0 : 25,
                    }}
                    animate={{ scale: 1, opacity: 1, rotate: 0 }}
                    exit={{
                      scale: prefersReducedMotion ? 1 : 0.70,
                      opacity: 0,
                      rotate: prefersReducedMotion ? 0 : -25,
                    }}
                    transition={{
                      duration: 0.18,
                      ease: [0.16, 1, 0.3, 1],
                    }}
                    className="flex items-center justify-center ml-0.5"
                  >
                    <Play className="w-4 h-4 fill-current" />
                  </motion.div>
                )}
              </AnimatePresence>
            </div>
          </motion.button>

          {/* Botón Pista Siguiente */}
          <motion.button
            whileTap={{ scale: prefersReducedMotion ? 1 : 0.88 }}
            whileHover={{ scale: prefersReducedMotion ? 1 : 1.05 }}
            transition={{
              type: 'spring',
              stiffness: 550,
              damping: 24,
              mass: 0.5,
            }}
            onClick={handleNext}
            className="w-8 h-8 flex items-center justify-center rounded-full text-white/70 hover:text-white hover:bg-white/10 active:bg-white/15 transition-colors focus:outline-none"
            title="Siguiente"
          >
            <SkipForward className="w-4 h-4 fill-current" />
          </motion.button>
        </div>

        {/* Volume Controls */}
        <div className="flex items-center space-x-2">
          <button
            onClick={toggleMute}
            className="text-white/50 hover:text-white transition p-1"
            title={isMuted ? 'Desactivar silencio' : 'Silenciar'}
          >
            {isMuted || volume === 0 ? (
              <VolumeX className="w-3.5 h-3.5 text-red-400" />
            ) : (
              <Volume2 className="w-3.5 h-3.5" />
            )}
          </button>
          <input
            type="range"
            min="0"
            max="1"
            step="0.05"
            value={isMuted ? 0 : volume}
            onChange={handleVolumeChange}
            className="w-16 h-1 bg-white/20 rounded-lg appearance-none cursor-pointer accent-white hover:h-1.5 transition-all"
          />
        </div>
      </div>
    </div>
  );
};
