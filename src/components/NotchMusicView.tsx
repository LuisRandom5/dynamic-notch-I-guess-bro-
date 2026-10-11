import React, { useState } from 'react';
import { 
  Play, 
  Pause, 
  SkipBack, 
  SkipForward, 
  Volume2, 
  VolumeX, 
  Shuffle, 
  Repeat, 
  Headphones, 
  Music2, 
  ListMusic 
} from 'lucide-react';
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

  return (
    <div className="w-full text-white select-none">
      {/* Top bar with output device and equalizer */}
      <div className="flex items-center justify-between text-xs text-white/50 mb-3 px-1">
        <button
          onClick={() => {
            setOutputDevice(d => (d === 'airpods' ? 'macbook' : 'airpods'));
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
              setShowPlaylist(p => !p);
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
                onClick={() => {
                  onSelectTrack(track);
                  setShowPlaylist(false);
                }}
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
          {/* Album Artwork */}
          <div className="relative group flex-shrink-0">
            <div
              className="w-16 h-16 sm:w-20 sm:h-20 rounded-2xl overflow-hidden shadow-2xl relative transition-transform duration-300 group-hover:scale-105 border border-white/10"
              style={{
                boxShadow: `0 10px 30px -5px ${currentTrack.color}50`,
              }}
            >
              <img
                src={currentTrack.coverUrl}
                alt={currentTrack.title}
                className={`w-full h-full object-cover transition-all ${
                  isPlaying ? 'brightness-105' : 'brightness-90'
                }`}
              />
              {/* Subtle vinyl groove overlay */}
              <div className="absolute inset-0 bg-gradient-to-tr from-black/40 via-transparent to-white/10 pointer-events-none" />
            </div>

            {isPlaying && (
              <span 
                className="absolute -bottom-1 -right-1 w-3.5 h-3.5 rounded-full border-2 border-black flex items-center justify-center animate-pulse"
                style={{ backgroundColor: currentTrack.color }}
              />
            )}
          </div>

          {/* Track Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center space-x-2">
              <span className="text-[10px] uppercase tracking-wider font-semibold px-1.5 py-0.5 rounded bg-white/10 text-white/70">
                {currentTrack.genre}
              </span>
            </div>

            <h4 className="text-base font-semibold tracking-tight text-white truncate mt-1">
              {currentTrack.title}
            </h4>
            <p className="text-xs text-white/60 truncate font-normal">
              {currentTrack.artist} · <span className="text-white/40">{currentTrack.album}</span>
            </p>

            {/* Interactive Timeline Scrubber */}
            <div className="mt-2.5">
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

        {/* Center Primary Controls */}
        <div className="flex items-center space-x-3">
          <button
            onClick={onPrevTrack}
            className="p-1.5 text-white/70 hover:text-white hover:scale-110 active:scale-95 transition"
            title="Anterior"
          >
            <SkipBack className="w-4 h-4 fill-current" />
          </button>

          <button
            onClick={onTogglePlay}
            className="w-9 h-9 rounded-full bg-white text-black flex items-center justify-center hover:scale-105 active:scale-95 transition-transform shadow-lg shadow-white/20"
            title={isPlaying ? 'Pausar' : 'Reproducir'}
          >
            {isPlaying ? (
              <Pause className="w-4 h-4 fill-current" />
            ) : (
              <Play className="w-4 h-4 fill-current ml-0.5" />
            )}
          </button>

          <button
            onClick={onNextTrack}
            className="p-1.5 text-white/70 hover:text-white hover:scale-110 active:scale-95 transition"
            title="Siguiente"
          >
            <SkipForward className="w-4 h-4 fill-current" />
          </button>
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
