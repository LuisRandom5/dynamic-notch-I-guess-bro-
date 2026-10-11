export type NotchState = 'idle' | 'compact' | 'expanded' | 'notification';

export type NotchStyle = 'macbook-pro' | 'macbook-air' | 'island-floating';

export interface Track {
  id: string;
  title: string;
  artist: string;
  album: string;
  duration: number; // in seconds
  coverUrl: string;
  color: string;
  genre: string;
}

export type NotificationType = 
  | 'airdrop'
  | 'magsafe'
  | 'timer'
  | 'battery_low'
  | 'mic_cam'
  | 'call'
  | 'clipboard';

export interface NotchNotification {
  id: string;
  type: NotificationType;
  title: string;
  subtitle: string;
  sender?: string;
  meta?: string;
  timestamp: number;
  duration?: number; // auto-dismiss seconds
  actionLabel?: string;
  secondaryLabel?: string;
  icon?: string;
  progress?: number;
}
