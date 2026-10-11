import React, { useState, useEffect } from 'react';
import { 
  Share2, 
  Zap, 
  Timer, 
  AlertTriangle, 
  Camera, 
  PhoneCall, 
  PhoneOff, 
  ClipboardCheck, 
  Check, 
  X,
  Play,
  Pause,
  ArrowDownToLine
} from 'lucide-react';
import { NotchNotification } from '../types/notch';
import { audioEngine } from '../utils/audioEngine';

interface NotchNotificationViewProps {
  notification: NotchNotification;
  onDismiss: () => void;
  onAction?: (action: string) => void;
}

export const NotchNotificationView: React.FC<NotchNotificationViewProps> = ({
  notification,
  onDismiss,
  onAction,
}) => {
  const [actionDone, setActionDone] = useState<string | null>(null);
  const [timerSeconds, setTimerSeconds] = useState(1499); // 24:59
  const [isTimerPaused, setIsTimerPaused] = useState(false);
  const [airDropProgress, setAirDropProgress] = useState(0);
  const [isDownloading, setIsDownloading] = useState(false);

  // Play notification chime on mount
  useEffect(() => {
    audioEngine.playHaptic('notification');
  }, [notification.id]);

  // Handle active timer countdown if type is timer
  useEffect(() => {
    if (notification.type !== 'timer' || isTimerPaused) return;
    const interval = setInterval(() => {
      setTimerSeconds(s => (s > 0 ? s - 1 : 0));
    }, 1000);
    return () => clearInterval(interval);
  }, [notification.type, isTimerPaused]);

  // Handle AirDrop accept download animation
  useEffect(() => {
    if (!isDownloading) return;
    const interval = setInterval(() => {
      setAirDropProgress(p => {
        if (p >= 100) {
          clearInterval(interval);
          setActionDone('Descargado con éxito');
          audioEngine.playHaptic('ding');
          return 100;
        }
        return p + 20;
      });
    }, 250);
    return () => clearInterval(interval);
  }, [isDownloading]);

  const handlePrimaryClick = () => {
    audioEngine.playHaptic('snap');
    if (notification.type === 'airdrop') {
      setIsDownloading(true);
      return;
    }
    if (notification.type === 'timer') {
      setIsTimerPaused(!isTimerPaused);
      return;
    }
    if (notification.type === 'call') {
      setActionDone('Llamada conectada...');
      return;
    }
    setActionDone('Acción completada');
    onAction?.(notification.actionLabel || 'Aceptar');
  };

  const handleSecondaryClick = () => {
    audioEngine.playHaptic('click');
    onDismiss();
  };

  const formatTimer = (totalSeconds: number) => {
    const mins = Math.floor(totalSeconds / 60);
    const secs = totalSeconds % 60;
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  };

  // Icon mapping
  const renderIcon = () => {
    switch (notification.type) {
      case 'airdrop':
        return (
          <div className="w-10 h-10 rounded-full bg-blue-500/20 border border-blue-400/30 flex items-center justify-center text-blue-400">
            <Share2 className="w-5 h-5 animate-pulse" />
          </div>
        );
      case 'magsafe':
        return (
          <div className="w-10 h-10 rounded-full bg-emerald-500/20 border border-emerald-400/30 flex items-center justify-center text-emerald-400">
            <Zap className="w-5 h-5 animate-bounce" />
          </div>
        );
      case 'timer':
        return (
          <div className="w-10 h-10 rounded-full bg-amber-500/20 border border-amber-400/30 flex items-center justify-center text-amber-400">
            <Timer className="w-5 h-5" />
          </div>
        );
      case 'battery_low':
        return (
          <div className="w-10 h-10 rounded-full bg-red-500/20 border border-red-400/30 flex items-center justify-center text-red-400">
            <AlertTriangle className="w-5 h-5 animate-pulse" />
          </div>
        );
      case 'mic_cam':
        return (
          <div className="w-10 h-10 rounded-full bg-emerald-500/20 border border-emerald-400/30 flex items-center justify-center text-emerald-400 relative">
            <Camera className="w-5 h-5" />
            <span className="absolute top-1 right-1 w-2 h-2 rounded-full bg-emerald-400 animate-ping" />
          </div>
        );
      case 'call':
        return (
          <div className="w-10 h-10 rounded-full bg-green-500/20 border border-green-400/30 flex items-center justify-center text-green-400">
            <PhoneCall className="w-5 h-5 animate-pulse" />
          </div>
        );
      case 'clipboard':
        return (
          <div className="w-10 h-10 rounded-full bg-purple-500/20 border border-purple-400/30 flex items-center justify-center text-purple-400">
            <ClipboardCheck className="w-5 h-5" />
          </div>
        );
      default:
        return (
          <div className="w-10 h-10 rounded-full bg-white/10 flex items-center justify-center text-white">
            <Check className="w-5 h-5" />
          </div>
        );
    }
  };

  return (
    <div className="w-full text-white select-none">
      {/* Main notification header */}
      <div className="flex items-start justify-between">
        <div className="flex items-center space-x-3.5 min-w-0">
          {renderIcon()}
          <div className="min-w-0">
            <div className="flex items-center space-x-2">
              <span className="text-[10px] tracking-wider uppercase font-semibold text-white/50">
                {notification.type.toUpperCase()}
              </span>
              {notification.meta && (
                <span className="text-[10px] text-white/40">· {notification.meta}</span>
              )}
            </div>
            <h4 className="text-sm font-semibold tracking-tight text-white truncate">
              {notification.title}
            </h4>
            <p className="text-xs text-white/70 line-clamp-2 mt-0.5">
              {notification.subtitle}
            </p>
          </div>
        </div>

        {/* Close Button */}
        <button
          onClick={handleSecondaryClick}
          className="text-white/40 hover:text-white p-1 rounded-full hover:bg-white/10 transition flex-shrink-0"
          title="Cerrar notificación"
        >
          <X className="w-4 h-4" />
        </button>
      </div>

      {/* Special Content based on notification type */}
      {notification.type === 'timer' && (
        <div className="mt-3 p-2.5 rounded-xl bg-white/5 border border-white/5 flex items-center justify-between">
          <div className="flex items-center space-x-2">
            <span className="text-2xl font-mono font-bold tracking-tight text-amber-300">
              {formatTimer(timerSeconds)}
            </span>
            <span className="text-xs text-white/50">
              {isTimerPaused ? '(Pausado)' : '(En curso)'}
            </span>
          </div>
          <button
            onClick={() => setTimerSeconds(s => s + 60)}
            className="text-xs px-2.5 py-1 rounded-lg bg-white/10 hover:bg-white/20 transition text-white/80"
          >
            +1 min
          </button>
        </div>
      )}

      {notification.type === 'magsafe' && (
        <div className="mt-3">
          <div className="w-full bg-white/10 h-2 rounded-full overflow-hidden">
            <div
              className="bg-emerald-400 h-full rounded-full transition-all duration-500 ease-out"
              style={{ width: `${notification.progress || 88}%` }}
            />
          </div>
          <div className="flex justify-between items-center text-[11px] text-white/50 mt-1.5">
            <span>Carga ultrarrápida 140W</span>
            <span className="text-emerald-400 font-semibold">{notification.progress || 88}%</span>
          </div>
        </div>
      )}

      {isDownloading && (
        <div className="mt-3 space-y-1">
          <div className="w-full bg-white/10 h-2 rounded-full overflow-hidden">
            <div
              className="bg-blue-400 h-full rounded-full transition-all duration-200"
              style={{ width: `${airDropProgress}%` }}
            />
          </div>
          <p className="text-[11px] text-blue-300 flex items-center space-x-1">
            <ArrowDownToLine className="w-3 h-3" />
            <span>Transfiriendo archivos... {airDropProgress}%</span>
          </p>
        </div>
      )}

      {/* Action buttons footer */}
      {actionDone ? (
        <div className="mt-3 py-1.5 px-3 rounded-xl bg-emerald-500/20 text-emerald-300 text-xs flex items-center justify-center space-x-1.5 font-medium border border-emerald-500/30">
          <Check className="w-4 h-4" />
          <span>{actionDone}</span>
        </div>
      ) : (
        <div className="mt-3.5 flex items-center justify-end space-x-2 pt-2 border-t border-white/[0.08]">
          {notification.secondaryLabel && (
            <button
              onClick={handleSecondaryClick}
              className="px-3.5 py-1.5 rounded-xl text-xs font-medium text-white/70 hover:text-white hover:bg-white/10 transition"
            >
              {notification.secondaryLabel}
            </button>
          )}

          {notification.actionLabel && (
            <button
              onClick={handlePrimaryClick}
              className={`px-4 py-1.5 rounded-xl text-xs font-semibold shadow-md transition flex items-center space-x-1.5 ${
                notification.type === 'call'
                  ? 'bg-emerald-500 text-white hover:bg-emerald-400 shadow-emerald-500/30'
                  : notification.type === 'battery_low'
                  ? 'bg-red-500 text-white hover:bg-red-400'
                  : 'bg-white text-black hover:bg-white/90 shadow-white/20'
              }`}
            >
              {notification.type === 'timer' && (
                isTimerPaused ? <Play className="w-3 h-3 fill-current" /> : <Pause className="w-3 h-3 fill-current" />
              )}
              <span>{notification.actionLabel}</span>
            </button>
          )}
        </div>
      )}
    </div>
  );
};
