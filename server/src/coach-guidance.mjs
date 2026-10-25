import { readFileSync } from 'node:fs';
const registry = JSON.parse(readFileSync(new URL('../../Shared/Core/Resources/coach-guidance.json', import.meta.url), 'utf8'));
if (registry.version !== 1 || !Array.isArray(registry.sources) || !registry.sources.length || new Set(registry.sources.map(source => source.id)).size !== registry.sources.length) throw Error('Invalid coach guidance registry.');
export const guidanceSources = registry.sources;
