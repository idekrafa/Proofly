create table if not exists public.pdf_signature_validations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  validation_token text not null unique,
  token_sha256 text not null unique,
  status text not null default 'issued'
    check (status in ('issued', 'finalized', 'revoked')),
  case_id uuid not null,
  source_export_id uuid,
  signed_export_id uuid,
  source_pdf_sha256 text,
  signed_pdf_sha256 text,
  signature_image_sha256 text not null,
  signature_page text not null,
  signature_placement text not null,
  signed_at timestamptz not null,
  issued_at timestamptz not null default now(),
  finalized_at timestamptz,
  revoked_at timestamptz,
  app_version text not null,
  pdf_export_mode text not null,
  include_statement_placeholder boolean not null default false,
  algorithm text not null,
  key_version text not null,
  manifest_sha256 text not null,
  manifest_signature text not null,
  encrypted_manifest text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.pdf_signature_validations enable row level security;

drop policy if exists "pdf signature validations owner read" on public.pdf_signature_validations;
create policy "pdf signature validations owner read"
  on public.pdf_signature_validations
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.pdf_signature_validations from public, anon, authenticated;
grant select on public.pdf_signature_validations to authenticated;

create index if not exists pdf_signature_validations_user_id_idx
  on public.pdf_signature_validations (user_id);

create index if not exists pdf_signature_validations_status_idx
  on public.pdf_signature_validations (status);

create index if not exists pdf_signature_validations_case_id_idx
  on public.pdf_signature_validations (case_id);
