import React, { useState } from 'react';
import { 
  Folder, 
  FileCode, 
  FileText, 
  Sparkles, 
  HelpCircle,
  ExternalLink,
  ChevronRight
} from 'lucide-react';
import { Track } from '../types/notch';
import { audioEngine } from '../utils/audioEngine';

interface MacDesktopProps {
  currentTrack: Track;
  isPlaying: boolean;
  onOpenNotchManual: () => void;
}

export const MacDesktop: React.FC<MacDesktopProps> = ({
  currentTrack,
  isPlaying,
  onOpenNotchManual,
}) => {
  const [showTip, setShowTip] = useState(true);

  // macOS Dock apps
  const dockApps = [
    { name: 'Finder', icon: 'https://cdn.iconscout.com/icon/free/png-256/free-finder-logo-icon-download-in-svg-png-gif-file-formats--apple-mac-os-pack-user-interface-icons-7001402.png', isCustom: false },
    { name: 'Safari', icon: '🧭', isCustom: true, bg: 'from-blue-500 to-cyan-400' },
    { name: 'Mensajes', icon: '💬', isCustom: true, bg: 'from-green-500 to-emerald-400' },
    { name: 'Música', icon: '🎵', isCustom: true, bg: 'from-pink-500 to-rose-500', active: isPlaying },
    { name: 'Fotos', icon: '🌸', isCustom: true, bg: 'from-amber-400 to-orange-500' },
    { name: 'Notas', icon: '📝', isCustom: true, bg: 'from-yellow-400 to-amber-500' },
    { name: 'Ajustes', icon: '⚙️', isCustom: true, bg: 'from-neutral-600 to-neutral-800' },
    { name: 'Terminal', icon: '⬛', isCustom: true, bg: 'from-black to-neutral-900' },
  ];

  return (
    <div className="relative w-full h-full flex flex-col justify-between p-4 pt-12 pb-24 select-none pointer-events-none">
      {/* Desktop items (Top-Right) */}
      <div className="self-end pointer-events-auto space-y-4 text-center mr-2">
        <div 
          onClick={() => audioEngine.playHaptic('snap')}
          className="flex flex-col items-center group cursor-pointer p-2 rounded-xl hover:bg-white/10 transition"
        >
          <div className="w-12 h-12 rounded-xl bg-blue-500/20 border border-blue-400/30 flex items-center justify-center text-blue-400 shadow-md group-hover:scale-105 transition">
            <Folder className="w-6 h-6 fill-blue-500/30" />
          </div>
          <span className="text-[11px] text-white/90 font-medium mt-1 drop-shadow-md">
            MacBook Pro M3
          </span>
        </div>

        <div 
          onClick={() => audioEngine.playHaptic('snap')}
          className="flex flex-col items-center group cursor-pointer p-2 rounded-xl hover:bg-white/10 transition"
        >
          <div className="w-12 h-12 rounded-xl bg-amber-500/20 border border-amber-400/30 flex items-center justify-center text-amber-300 shadow-md group-hover:scale-105 transition">
            <FileCode className="w-6 h-6" />
          </div>
          <span className="text-[11px] text-white/90 font-medium mt-1 drop-shadow-md">
            DynamicIsland.tsx
          </span>
        </div>
      </div>

      {/* Floating Welcome / Instruction Tip Card */}
      {showTip && (
        <div className="pointer-events-auto max-w-sm ml-4 mb-4 bg-black/60 backdrop-blur-2xl border border-white/15 p-4 rounded-3xl text-white shadow-2xl relative">
          <button
            onClick={() => setShowTip(false)}
            className="absolute top-3 right-3 text-white/40 hover:text-white text-xs p-1"
          >
            ✕
          </button>
          <div className="flex items-center space-x-2 text-cyan-400 mb-1.5">
            <Sparkles className="w-4 h-4" />
            <h4 className="text-xs font-semibold tracking-tight uppercase">
              Isla Dinámica para el Notch de Mac
            </h4>
          </div>
          <p className="text-xs text-white/80 leading-relaxed">
            Convierte el notch negro de las MacBook en una superficie interactiva fluida. 
            <strong> Pasa el cursor o haz clic en el notch arriba</strong> para desplegar el reproductor o ver las notificaciones activas.
          </p>

          <div className="mt-3 flex items-center justify-between pt-2 border-t border-white/10">
            <button
              onClick={onOpenNotchManual}
              className="text-xs text-cyan-300 hover:text-cyan-200 font-medium flex items-center space-x-1"
            >
              <span>Abrir Notch ahora</span>
              <ChevronRight className="w-3.5 h-3.5" />
            </button>
            <span className="text-[10px] text-white/40">v1.0 Preview</span>
          </div>
        </div>
      )}

      {/* Realistic macOS Dock */}
      <div className="fixed bottom-24 sm:bottom-28 left-1/2 -translate-x-1/2 pointer-events-auto z-20">
        <div className="flex items-end space-x-2 px-3 py-2 bg-white/[0.12] backdrop-blur-3xl border border-white/20 rounded-2xl shadow-[0_20px_50px_rgba(0,0,0,0.5)]">
          {dockApps.map((app, i) => (
            <div
              key={i}
              onClick={() => {
                audioEngine.playHaptic('snap');
              }}
              className="relative group flex flex-col items-center cursor-pointer transition-transform duration-200 hover:-translate-y-2 hover:scale-110 active:scale-95"
            >
              {/* App Icon */}
              <div 
                className={`w-10 h-10 sm:w-11 sm:h-11 rounded-xl flex items-center justify-center text-lg shadow-lg border border-white/10 ${
                  app.isCustom ? `bg-gradient-to-tr ${app.bg}` : 'bg-white/10'
                }`}
              >
                {app.icon}
              </div>

              {/* Running indicator dot */}
              {app.active && (
                <span className="w-1 h-1 bg-white rounded-full mt-1 -mb-1 shadow" />
              )}

              {/* Tooltip */}
              <div className="absolute -top-8 px-2 py-0.5 rounded-md bg-black/80 backdrop-blur-md text-[10px] text-white font-medium opacity-0 group-hover:opacity-100 transition pointer-events-none whitespace-nowrap shadow-lg border border-white/10">
                {app.name}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
