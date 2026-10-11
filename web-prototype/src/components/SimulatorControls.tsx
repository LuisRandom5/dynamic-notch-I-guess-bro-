import React, { useState } from 'react';
import { 
  Bell, 
  Music, 
  Share2, 
  Zap, 
  Timer, 
  AlertTriangle, 
  Camera, 
  PhoneCall, 
  Image, 
  Volume2, 
  VolumeX, 
  Sparkles, 
  Sliders, 
  Eye, 
  EyeOff, 
  Play, 
  Pause, 
  SkipForward,
  Info
} from 'lucide-react';
import { NOTIFICATION_PRESETS, WALLPAPER_PRESETS } from '../utils/mockData';
import { NotchNotification, Track } from '../types/notch';
import { audioEngine } from '../utils/audioEngine';

interface SimulatorControlsProps {
  currentTrack: Track;
  isPlaying: boolean;
  onTogglePlay: () => void;
  onNextTrack: () => void;
  onTriggerNotification: (notif: NotchNotification) => void;
  onClearNotification: () => void;
  hasActiveNotification: boolean;
  selectedWallpaper: string;
  onSelectWallpaper: (url: string) => void;
  expandOnHover: boolean;
  onToggleExpandOnHover: () => void;
  soundEffects: boolean;
  onToggleSoundEffects: () => void;
  isRealNotchMode: boolean;
  onToggleRealNotchMode: () => void;
}

export const SimulatorControls: React.FC<SimulatorControlsProps> = ({
  currentTrack,
  isPlaying,
  onTogglePlay,
  onNextTrack,
  onTriggerNotification,
  onClearNotification,
  hasActiveNotification,
  selectedWallpaper,
  onSelectWallpaper,
  expandOnHover,
  onToggleExpandOnHover,
  soundEffects,
  onToggleSoundEffects,
  isRealNotchMode,
  onToggleRealNotchMode,
}) => {
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [activeCategory, setActiveCategory] = useState<'notifications' | 'music' | 'settings'>('notifications');

  return (
    <div className="fixed bottom-4 left-1/2 -translate-x-1/2 z-40 max-w-4xl w-[94%] sm:w-[88%] select-none">
      {/* Floating control dock */}
      <div className="bg-black/80 backdrop-blur-3xl border border-white/15 rounded-3xl p-3 sm:p-4 shadow-[0_20px_50px_rgba(0,0,0,0.8)] text-white">
        <div className="flex items-center justify-between pb-2 mb-2.5 border-b border-white/10">
          <div className="flex items-center space-x-2">
            <div className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
            <h3 className="text-xs sm:text-sm font-semibold tracking-tight text-white flex items-center gap-1.5">
              <span>Mac Dynamic Notch Simulator</span>
              <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-white/10 text-cyan-300 font-normal">
                v1.0
              </span>
            </h3>
          </div>

          {/* Category Tabs */}
          <div className="flex items-center space-x-1 bg-white/5 p-0.5 rounded-xl text-xs">
            <button
              onClick={() => {
                setActiveCategory('notifications');
                audioEngine.playHaptic('click');
              }}
              className={`px-2.5 py-1 rounded-lg transition font-medium flex items-center space-x-1 ${
                activeCategory === 'notifications'
                  ? 'bg-white/20 text-white shadow-sm'
                  : 'text-white/60 hover:text-white'
              }`}
            >
              <Bell className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Notificaciones</span>
            </button>

            <button
              onClick={() => {
                setActiveCategory('music');
                audioEngine.playHaptic('click');
              }}
              className={`px-2.5 py-1 rounded-lg transition font-medium flex items-center space-x-1 ${
                activeCategory === 'music'
                  ? 'bg-white/20 text-white shadow-sm'
                  : 'text-white/60 hover:text-white'
              }`}
            >
              <Music className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Música</span>
            </button>

            <button
              onClick={() => {
                setActiveCategory('settings');
                audioEngine.playHaptic('click');
              }}
              className={`px-2.5 py-1 rounded-lg transition font-medium flex items-center space-x-1 ${
                activeCategory === 'settings'
                  ? 'bg-white/20 text-white shadow-sm'
                  : 'text-white/60 hover:text-white'
              }`}
            >
              <Sliders className="w-3.5 h-3.5" />
              <span className="hidden sm:inline">Ajustes</span>
            </button>
          </div>

          <div className="flex items-center space-x-1.5">
            <button
              onClick={onToggleRealNotchMode}
              className={`text-xs px-2.5 py-1 rounded-xl transition font-medium flex items-center space-x-1.5 ${
                isRealNotchMode 
                  ? 'bg-cyan-500 text-black shadow-md shadow-cyan-500/20' 
                  : 'bg-white/10 hover:bg-white/20 text-white'
              }`}
              title="Alternar entre simulación de escritorio y solo el Notch"
            >
              <span>{isRealNotchMode ? '💻 Volver al Escritorio' : '⚡ Modo Notch Real'}</span>
            </button>

            <button
              onClick={() => setIsCollapsed(!isCollapsed)}
              className="p-1.5 rounded-xl hover:bg-white/10 text-white/50 hover:text-white transition"
              title={isCollapsed ? 'Expandir panel de pruebas' : 'Minimizar panel'}
            >
              {isCollapsed ? <Eye className="w-4 h-4" /> : <EyeOff className="w-4 h-4" />}
            </button>
          </div>
        </div>

        {!isCollapsed && (
          <div>
            {/* Notifications Test Category */}
            {activeCategory === 'notifications' && (
              <div>
                <p className="text-[11px] text-white/50 mb-2">
                  Prueba animaciones en el notch activando notificaciones del sistema macOS:
                </p>
                <div className="grid grid-cols-2 sm:grid-cols-4 md:grid-cols-7 gap-1.5">
                  {NOTIFICATION_PRESETS.map((notif) => (
                    <button
                      key={notif.id}
                      onClick={() => {
                        onTriggerNotification(notif);
                        audioEngine.playHaptic('notification');
                      }}
                      className="flex flex-col items-center justify-center p-2 rounded-xl bg-white/5 hover:bg-white/15 border border-white/5 hover:border-white/20 transition-all text-center group active:scale-95"
                    >
                      <div className="w-7 h-7 rounded-lg bg-white/10 flex items-center justify-center mb-1 group-hover:scale-110 transition">
                        {notif.type === 'airdrop' && <Share2 className="w-3.5 h-3.5 text-blue-400" />}
                        {notif.type === 'magsafe' && <Zap className="w-3.5 h-3.5 text-emerald-400" />}
                        {notif.type === 'timer' && <Timer className="w-3.5 h-3.5 text-amber-400" />}
                        {notif.type === 'battery_low' && <AlertTriangle className="w-3.5 h-3.5 text-red-400" />}
                        {notif.type === 'mic_cam' && <Camera className="w-3.5 h-3.5 text-emerald-400" />}
                        {notif.type === 'call' && <PhoneCall className="w-3.5 h-3.5 text-green-400" />}
                        {notif.type === 'clipboard' && <Sparkles className="w-3.5 h-3.5 text-purple-400" />}
                      </div>
                      <span className="text-[11px] font-medium text-white/90 truncate w-full">
                        {notif.title.split(' ')[0]}
                      </span>
                      <span className="text-[9px] text-white/40 truncate w-full capitalize">
                        {notif.type.replace('_', ' ')}
                      </span>
                    </button>
                  ))}
                </div>

                {hasActiveNotification && (
                  <div className="mt-2.5 flex justify-end">
                    <button
                      onClick={onClearNotification}
                      className="text-xs px-3 py-1 rounded-lg bg-white/10 hover:bg-white/20 text-white/70 hover:text-white transition"
                    >
                      Descartar notificación activa
                    </button>
                  </div>
                )}
              </div>
            )}

            {/* Music Test Category */}
            {activeCategory === 'music' && (
              <div className="flex flex-col sm:flex-row items-center justify-between gap-3">
                <div className="flex items-center space-x-3 w-full sm:w-auto">
                  <img
                    src={currentTrack.coverUrl}
                    alt={currentTrack.title}
                    className="w-10 h-10 rounded-xl object-cover shadow-md"
                  />
                  <div>
                    <h4 className="text-xs font-semibold text-white truncate max-w-[200px]">
                      {currentTrack.title}
                    </h4>
                    <p className="text-[11px] text-white/50">{currentTrack.artist}</p>
                  </div>
                </div>

                <div className="flex items-center space-x-2">
                  <button
                    onClick={onTogglePlay}
                    className="px-4 py-1.5 rounded-xl bg-white text-black font-semibold text-xs flex items-center space-x-1.5 hover:bg-white/90 active:scale-95 transition"
                  >
                    {isPlaying ? <Pause className="w-3.5 h-3.5 fill-current" /> : <Play className="w-3.5 h-3.5 fill-current" />}
                    <span>{isPlaying ? 'Pausar Sintetizador' : 'Reproducir Sintetizador'}</span>
                  </button>

                  <button
                    onClick={onNextTrack}
                    className="p-2 rounded-xl bg-white/10 hover:bg-white/20 text-white/80 hover:text-white transition"
                    title="Siguiente pista"
                  >
                    <SkipForward className="w-3.5 h-3.5" />
                  </button>
                </div>
              </div>
            )}

            {/* Settings & Wallpaper */}
            {activeCategory === 'settings' && (
              <div className="space-y-3">
                <div className="flex flex-wrap items-center justify-between gap-2 text-xs">
                  {/* Expand on hover toggle */}
                  <label className="flex items-center space-x-2 cursor-pointer p-1.5 rounded-xl hover:bg-white/5">
                    <input
                      type="checkbox"
                      checked={expandOnHover}
                      onChange={onToggleExpandOnHover}
                      className="rounded accent-cyan-400"
                    />
                    <span className="text-white/80 text-[11px]">
                      Expandir isla automáticamente al pasar el cursor (Hover)
                    </span>
                  </label>

                  {/* Sound effects toggle */}
                  <label className="flex items-center space-x-2 cursor-pointer p-1.5 rounded-xl hover:bg-white/5">
                    <input
                      type="checkbox"
                      checked={soundEffects}
                      onChange={onToggleSoundEffects}
                      className="rounded accent-cyan-400"
                    />
                    <span className="text-white/80 text-[11px] flex items-center gap-1">
                      {soundEffects ? <Volume2 className="w-3 h-3 text-cyan-400" /> : <VolumeX className="w-3 h-3 text-white/40" />}
                      Efectos hápticos de sonido Apple
                    </span>
                  </label>
                </div>

                {/* Wallpapers */}
                <div>
                  <span className="text-[10px] uppercase font-semibold text-white/50 block mb-1.5">
                    Fondos de pantalla macOS
                  </span>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {WALLPAPER_PRESETS.map((wp) => (
                      <button
                        key={wp.id}
                        onClick={() => {
                          onSelectWallpaper(wp.url);
                          audioEngine.playHaptic('snap');
                        }}
                        className={`p-1.5 rounded-xl border text-left flex items-center space-x-2 transition ${
                          selectedWallpaper === wp.url
                            ? 'border-cyan-400 bg-cyan-500/10'
                            : 'border-white/10 hover:border-white/20 bg-white/5'
                        }`}
                      >
                        <img
                          src={wp.url}
                          alt={wp.name}
                          className="w-6 h-6 rounded-lg object-cover"
                        />
                        <span className="text-[11px] text-white/80 truncate">{wp.name}</span>
                      </button>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
