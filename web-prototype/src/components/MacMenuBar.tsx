import React, { useState, useEffect } from 'react';
import { 
  Wifi, 
  Battery, 
  Search, 
  SlidersHorizontal, 
  Volume2, 
  Sparkles,
  Command
} from 'lucide-react';

interface MacMenuBarProps {
  appName?: string;
  isAudioPlaying?: boolean;
  onOpenControls?: () => void;
  batteryLevel?: number;
  isCharging?: boolean;
}

export const MacMenuBar: React.FC<MacMenuBarProps> = ({
  appName = 'Música',
  isAudioPlaying = false,
  onOpenControls,
  batteryLevel = 88,
  isCharging = false,
}) => {
  const [timeStr, setTimeStr] = useState('');

  useEffect(() => {
    const updateTime = () => {
      const now = new Date();
      // Format like macOS: "dom 11 oct 16:45"
      const days = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      const dayName = days[now.getDay()];
      const dayNum = now.getDate();
      const monthName = months[now.getMonth()];
      const hours = String(now.getHours()).padStart(2, '0');
      const mins = String(now.getMinutes()).padStart(2, '0');
      setTimeStr(`${dayName} ${dayNum} ${monthName}  ${hours}:${mins}`);
    };

    updateTime();
    const interval = setInterval(updateTime, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <header className="relative w-full h-[32px] px-3 flex items-center justify-between text-[13px] font-sans text-white/90 bg-black/35 backdrop-blur-2xl border-b border-white/[0.08] select-none z-30 tracking-tight">
      {/* Left Menu Items */}
      <div className="flex items-center space-x-4">
        {/* Apple Logo */}
        <button 
          className="hover:bg-white/10 px-1.5 py-0.5 rounded transition cursor-default flex items-center"
          title="Menú Apple"
        >
          <svg className="w-3.5 h-3.5 fill-current" viewBox="0 0 170 170">
            <path d="M150.37 130.25c-2.45 5.66-5.35 10.87-8.71 15.66-4.58 6.53-8.33 11.05-11.22 13.56-4.48 4.12-9.28 6.23-14.42 6.35-3.69 0-8.14-1.05-13.32-3.18-5.19-2.12-9.97-3.17-14.34-3.17-4.58 0-9.49 1.05-14.75 3.17-5.26 2.13-9.5 3.24-12.74 3.35-4.35.13-9.16-1.9-14.42-6.08-3.7-3.08-7.72-7.87-12.06-14.36-6.3-9.41-11.23-20.2-14.78-32.36-3.55-12.16-5.33-23.75-5.33-34.77 0-14.18 3.55-26.04 10.66-35.59 7.1-9.54 16.14-14.42 27.12-14.63 4.8 0 10.23 1.34 16.3 4.02 6.07 2.68 9.99 4.07 11.75 4.18 1.57 0 5.66-1.46 12.28-4.39 6.62-2.93 12.28-4.22 16.99-3.87 13.43 1.05 23.95 6.4 31.57 16.06-11.97 7.24-17.84 17.27-17.62 30.1.22 10.15 4.13 18.67 11.73 25.56 5.25 4.83 11.13 8.01 17.63 9.54-2.52 7.52-5.55 15.11-9.07 22.78zM119.22 31.84c0-7.39 2.64-14.28 7.93-20.67 5.29-6.39 11.83-10.42 19.63-12.09.22 1.34.33 2.57.33 3.69 0 7.39-2.73 14.51-8.19 21.36-5.46 6.85-12.12 10.97-19.98 12.36-.22-1.57-.33-3.13-.33-4.65z" />
          </svg>
        </button>

        {/* Current Active App */}
        <span className="font-semibold tracking-normal text-white">{appName}</span>

        {/* Menu Items */}
        <span className="hidden sm:inline-block text-white/80 hover:text-white cursor-default px-1 py-0.5 rounded hover:bg-white/10 transition">
          Archivo
        </span>
        <span className="hidden sm:inline-block text-white/80 hover:text-white cursor-default px-1 py-0.5 rounded hover:bg-white/10 transition">
          Edición
        </span>
        <span className="hidden md:inline-block text-white/80 hover:text-white cursor-default px-1 py-0.5 rounded hover:bg-white/10 transition">
          Visualización
        </span>
        <span className="hidden lg:inline-block text-white/80 hover:text-white cursor-default px-1 py-0.5 rounded hover:bg-white/10 transition">
          Controles
        </span>
        <span className="hidden xl:inline-block text-white/80 hover:text-white cursor-default px-1 py-0.5 rounded hover:bg-white/10 transition">
          Ventana
        </span>
      </div>

      {/* Spacer for the Notch in the center */}
      <div className="w-[180px] pointer-events-none" aria-hidden="true" />

      {/* Right Menu Items (System Tray / Control Center) */}
      <div className="flex items-center space-x-2 sm:space-x-3 text-white/85">
        {/* Audio active icon */}
        {isAudioPlaying && (
          <div className="flex items-center text-green-400 space-x-1 px-1.5 py-0.5 rounded bg-green-500/10">
            <Volume2 className="w-3.5 h-3.5" />
          </div>
        )}

        {/* Battery */}
        <div className="flex items-center space-x-1 text-xs">
          <span className="hidden sm:inline text-[11px] tabular-nums font-medium text-white/75">
            {batteryLevel}%
          </span>
          <div className="relative flex items-center">
            <Battery className={`w-4 h-4 ${batteryLevel < 20 ? 'text-amber-400' : 'text-white/85'}`} />
            {isCharging && (
              <span className="absolute -top-0.5 right-0.5 w-1.5 h-1.5 bg-green-400 rounded-full animate-ping" />
            )}
          </div>
        </div>

        {/* Wi-Fi */}
        <Wifi className="w-3.5 h-3.5 text-white/85" />

        {/* Spotlight */}
        <Search className="w-3.5 h-3.5 text-white/85 hidden sm:inline" />

        {/* Control Center Toggle */}
        <button
          onClick={onOpenControls}
          className="hover:bg-white/10 p-1 rounded transition flex items-center"
          title="Centro de Control / Configuración de la Isla"
        >
          <SlidersHorizontal className="w-3.5 h-3.5 text-white/85" />
        </button>

        {/* Siri / AI Assist */}
        <div className="w-3.5 h-3.5 rounded-full bg-gradient-to-tr from-cyan-400 via-purple-400 to-pink-400 p-[1px] hidden sm:flex items-center justify-center">
          <div className="w-full h-full bg-black/60 rounded-full" />
        </div>

        {/* Date and Time */}
        <span className="text-[12px] tabular-nums tracking-normal font-medium text-white/95 pl-1">
          {timeStr || '16:20'}
        </span>
      </div>
    </header>
  );
};
