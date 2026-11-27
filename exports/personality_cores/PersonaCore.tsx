import React, { useEffect, useRef } from 'react';
import {
  mountPersonaCore,
  normalizePersonaId,
  PERSONA_CORES,
  type MountedPersonaCore,
  type PersonaCoreId,
} from './personality_cores.js';

export interface PersonaCoreProps {
  persona?: PersonaCoreId | string;
  energy?: number;
  size?: number;
  accentColor?: string;
  active?: boolean;
  showStarfield?: boolean;
  className?: string;
  style?: React.CSSProperties;
}

export const PersonaCore: React.FC<PersonaCoreProps> = ({
  persona = 'ultron',
  energy = 0.2,
  size = 240,
  accentColor,
  active = true,
  showStarfield = false,
  className,
  style,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const controllerRef = useRef<MountedPersonaCore | null>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;
    const ctrl = mountPersonaCore(canvas, {
      persona,
      energy,
      accentColor,
      active,
      showStarfield,
    });
    controllerRef.current = ctrl;
    return () => {
      ctrl.destroy();
      controllerRef.current = null;
    };
    // Mount once per canvas lifecycle; live prop changes sync below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    controllerRef.current?.setPersona(persona);
  }, [persona]);

  useEffect(() => {
    controllerRef.current?.setEnergy(energy);
  }, [energy]);

  useEffect(() => {
    controllerRef.current?.setAccentColor(accentColor ?? null);
  }, [accentColor]);

  useEffect(() => {
    controllerRef.current?.setActive(active);
  }, [active]);

  useEffect(() => {
    controllerRef.current?.setShowStarfield(showStarfield);
  }, [showStarfield]);

  const spec = PERSONA_CORES[normalizePersonaId(persona)];

  return (
    <canvas
      ref={canvasRef}
      aria-label={`Núcleo ${spec.displayName}`}
      className={className}
      style={{
        width: size,
        height: size,
        display: 'block',
        ...style,
      }}
    />
  );
};

export default PersonaCore;
