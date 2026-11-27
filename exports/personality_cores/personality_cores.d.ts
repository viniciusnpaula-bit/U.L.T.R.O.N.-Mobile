export type PersonaCoreId = 'ultron' | 'jarvis' | 'visao' | 'edith';

export interface PersonaCoreSpec {
  readonly id: PersonaCoreId;
  readonly displayName: string;
  readonly tagline: string;
  readonly themeName: string;
  readonly accentColor: string;
  readonly accentDark: string;
  readonly accentBorder: string;
  readonly highlightColor: string;
  readonly defaultStyle: string;
  readonly promptDirective: string;
  readonly geometry: string;
}

export declare const PERSONA_CORES: Readonly<Record<PersonaCoreId, PersonaCoreSpec>>;

export interface PaintCoreOptions {
  persona?: PersonaCoreId | string;
  energy?: number;
  accentColor?: string | null;
}

export interface PaintStarfieldOptions extends PaintCoreOptions {
  starCount?: number;
  nebulaIntensity?: number;
  centerX?: number;
  centerY?: number;
}

export interface MountPersonaCoreOptions extends PaintStarfieldOptions {
  active?: boolean;
  showStarfield?: boolean;
}

export interface MountedPersonaCore {
  setPersona(persona: PersonaCoreId | string): void;
  setEnergy(energy: number): void;
  setAccentColor(color: string | null): void;
  setActive(active: boolean): void;
  setShowStarfield(show: boolean): void;
  destroy(): void;
}

export declare function normalizePersonaId(raw?: string | null): PersonaCoreId;

export declare function paintStarfield(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  time: number,
  options?: PaintStarfieldOptions,
): void;

export declare function paintPersonaCore(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  time: number,
  options?: PaintCoreOptions,
): void;

export declare function mountPersonaCore(
  canvas: HTMLCanvasElement,
  initialOptions?: MountPersonaCoreOptions,
): MountedPersonaCore;
