import React, { useState } from 'react';
import { UploadCloud, FileText, Link2, Copy, Check, Trash2 } from 'lucide-react';
import { audioEngine } from '../utils/audioEngine';

interface StashedItem {
  id: string;
  name: string;
  type: 'file' | 'link' | 'note';
  sizeOrInfo: string;
  content: string;
}

export const NotchDropZone: React.FC = () => {
  const [items, setItems] = useState<StashedItem[]>([
    {
      id: 'item-1',
      name: 'Captura_pantalla_Mac.png',
      type: 'file',
      sizeOrInfo: '2.4 MB · Imagen PNG',
      content: 'image',
    },
    {
      id: 'item-2',
      name: 'https://apple.com/macbook-pro',
      type: 'link',
      sizeOrInfo: 'Enlace web guardado',
      content: 'https://apple.com/macbook-pro',
    },
  ]);
  const [isDragging, setIsDragging] = useState(false);
  const [copiedId, setCopiedId] = useState<string | null>(null);

  const handleCopy = (item: StashedItem) => {
    navigator.clipboard?.writeText(item.content);
    setCopiedId(item.id);
    audioEngine.playHaptic('snap');
    setTimeout(() => setCopiedId(null), 1800);
  };

  const handleDelete = (id: string) => {
    setItems(items.filter(it => it.id !== id));
    audioEngine.playHaptic('click');
  };

  const handleSimulateDrop = () => {
    const newItem: StashedItem = {
      id: `item-${Date.now()}`,
      name: `Nota_rápida_${items.length + 1}.txt`,
      type: 'note',
      sizeOrInfo: '1.2 KB · Nota rápida',
      content: 'Texto guardado rápidamente en el Notch Shelf.',
    };
    setItems([newItem, ...items]);
    audioEngine.playHaptic('ding');
  };

  return (
    <div className="w-full text-white select-none">
      <div className="flex items-center justify-between mb-2 px-1">
        <span className="text-[11px] font-semibold tracking-wider uppercase text-white/50">
          Notch Shelf (Bandeja Rápida)
        </span>
        <button
          onClick={handleSimulateDrop}
          className="text-[11px] px-2 py-0.5 rounded-full bg-white/10 hover:bg-white/20 text-white/80 transition"
        >
          + Añadir nota
        </button>
      </div>

      {/* Drag & Drop Target Area */}
      <div
        onDragOver={(e) => {
          e.preventDefault();
          setIsDragging(true);
        }}
        onDragLeave={() => setIsDragging(false)}
        onDrop={(e) => {
          e.preventDefault();
          setIsDragging(false);
          handleSimulateDrop();
        }}
        className={`w-full p-4 border border-dashed rounded-2xl flex flex-col items-center justify-center transition-all ${
          isDragging 
            ? 'border-cyan-400 bg-cyan-500/10 scale-[1.01]' 
            : 'border-white/15 bg-white/[0.03] hover:border-white/25 hover:bg-white/[0.06]'
        }`}
      >
        <UploadCloud className="w-6 h-6 text-white/40 mb-1" />
        <p className="text-xs font-medium text-white/70">
          Arrastra y suelta archivos o enlaces aquí
        </p>
        <p className="text-[10px] text-white/40 mt-0.5">
          Quedarán fijados en el notch para compartirlos rápidamente
        </p>
      </div>

      {/* Stashed Items List */}
      <div className="mt-3 space-y-1.5 max-h-[140px] overflow-y-auto pr-1">
        {items.map((item) => (
          <div
            key={item.id}
            className="flex items-center justify-between p-2 rounded-xl bg-white/5 hover:bg-white/10 transition border border-white/5 group"
          >
            <div className="flex items-center space-x-2.5 min-w-0">
              <div className="w-7 h-7 rounded-lg bg-white/10 flex items-center justify-center flex-shrink-0 text-white/70">
                {item.type === 'file' && <FileText className="w-3.5 h-3.5 text-blue-400" />}
                {item.type === 'link' && <Link2 className="w-3.5 h-3.5 text-emerald-400" />}
                {item.type === 'note' && <FileText className="w-3.5 h-3.5 text-amber-400" />}
              </div>
              <div className="min-w-0">
                <p className="text-xs font-medium text-white truncate max-w-[240px]">{item.name}</p>
                <p className="text-[10px] text-white/40 truncate">{item.sizeOrInfo}</p>
              </div>
            </div>

            <div className="flex items-center space-x-1 opacity-80 group-hover:opacity-100">
              <button
                onClick={() => handleCopy(item)}
                className="p-1 rounded-lg hover:bg-white/10 text-white/60 hover:text-white transition"
                title="Copiar"
              >
                {copiedId === item.id ? <Check className="w-3.5 h-3.5 text-emerald-400" /> : <Copy className="w-3.5 h-3.5" />}
              </button>
              <button
                onClick={() => handleDelete(item.id)}
                className="p-1 rounded-lg hover:bg-white/10 text-white/40 hover:text-red-400 transition"
                title="Eliminar"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
