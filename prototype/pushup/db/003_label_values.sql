-- Real sessions are labeled from the app's own posture cues, which also include hips piking and other issues.
ALTER TABLE pushup.rep DROP CONSTRAINT IF EXISTS rep_label_check;
ALTER TABLE pushup.rep ADD CONSTRAINT rep_label_check CHECK (label IN ('good', 'shallow', 'sagging', 'fatigued', 'piking', 'other'));
