alter table public.events add column if not exists poster_url text;
create index if not exists events_box_starts_idx on public.events(box_id, starts_at);
