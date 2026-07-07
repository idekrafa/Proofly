create table if not exists public.pdf_signature_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  case_id uuid not null,
  source_export_id uuid,
  request_token text not null unique,
  request_token_sha256 text not null unique,
  status text not null default 'pending'
    check (status in ('pending', 'signed', 'cancelled', 'expired')),
  document_title text not null,
  requester_name text,
  message text,
  signature_page text not null,
  signature_placement text not null,
  pdf_storage_path text not null,
  pdf_sha256 text not null,
  signer_name text,
  signer_ip text,
  signer_user_agent text,
  signature_image_path text,
  signature_image_sha256 text,
  consent_text text,
  signed_at timestamptz,
  expires_at timestamptz not null,
  cancelled_at timestamptz,
  app_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.pdf_signature_requests enable row level security;

drop policy if exists "pdf signature requests owner read" on public.pdf_signature_requests;
create policy "pdf signature requests owner read"
  on public.pdf_signature_requests
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.pdf_signature_requests from public, anon, authenticated;
grant select on public.pdf_signature_requests to authenticated;

create index if not exists pdf_signature_requests_user_id_idx
  on public.pdf_signature_requests (user_id);

create index if not exists pdf_signature_requests_case_id_idx
  on public.pdf_signature_requests (case_id);

create index if not exists pdf_signature_requests_status_idx
  on public.pdf_signature_requests (status);

-- Private bucket holding the unsigned source PDF and the counterparty's
-- signature image. Accessed only through Edge Functions with the service role.
insert into storage.buckets (id, name, public)
values ('signature-requests', 'signature-requests', false)
on conflict (id) do nothing;
