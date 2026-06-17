-- SAVE V1 schema draft for Kai HSA/FSA reimbursement and medical tax recovery.
-- This intentionally lives beside the older points/deals schema until the pivot is migrated.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

do $$
begin
  create type public.source_connection_kind as enum ('gmail', 'bank', 'forwarding_inbox');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.source_connection_status as enum ('not_connected', 'connected', 'failed', 'revoked');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.receipt_source_kind as enum ('camera', 'photo_library', 'forwarded_email', 'gmail', 'bank_match');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.receipt_status as enum ('importing', 'ocr_processing', 'needs_review', 'classified', 'failed');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.eligibility_classification as enum ('fsa_eligible', 'hsa_eligible', 'schedule_a_deductible', 'not_eligible', 'needs_review');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.claim_packet_status as enum ('draft', 'ready', 'submitted_by_user', 'submitted_in_app', 'needs_action', 'reimbursed', 'rejected');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.submission_mode as enum ('guided_packet', 'in_app_submission');
exception when duplicate_object then null;
end $$;

do $$
begin
  create type public.tax_export_status as enum ('draft', 'generated', 'failed');
exception when duplicate_object then null;
end $$;

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  display_name text,
  default_tax_year integer not null default extract(year from now())::integer,
  phi_retention_years integer not null default 7 check (phi_retention_years between 1 and 10),
  delete_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.mvp_progress_snapshots (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.source_connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind public.source_connection_kind not null,
  status public.source_connection_status not null default 'not_connected',
  provider_account_label text,
  last_synced_at timestamptz,
  error_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, kind)
);

create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source public.receipt_source_kind not null,
  status public.receipt_status not null default 'importing',
  merchant text,
  purchased_at date,
  total_amount numeric(12, 2),
  raw_ocr_text text,
  source_metadata jsonb not null default '{}'::jsonb,
  failure_reason text,
  excluded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.receipt_files (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  receipt_id uuid not null references public.receipts(id) on delete cascade,
  bucket_id text not null default 'receipt-files',
  object_path text not null,
  mime_type text,
  byte_size bigint,
  sha256 text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (bucket_id, object_path)
);

create table if not exists public.receipt_line_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  receipt_id uuid not null references public.receipts(id) on delete cascade,
  original_text text,
  normalized_name text not null,
  amount numeric(12, 2) not null check (amount >= 0),
  eligibility public.eligibility_classification not null default 'needs_review',
  confidence numeric(4, 3) not null default 0 check (confidence >= 0 and confidence <= 1),
  explanation text,
  evidence_labels text[] not null default '{}',
  user_override public.eligibility_classification,
  override_reason text,
  override_at timestamptz,
  excluded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.classification_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  receipt_id uuid references public.receipts(id) on delete set null,
  model_name text not null,
  taxonomy_version text not null,
  input_hash text not null,
  output_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.administrator_templates (
  id uuid primary key default gen_random_uuid(),
  administrator_name text not null,
  template_version text not null,
  supported_submission_mode public.submission_mode not null default 'guided_packet',
  required_fields jsonb not null default '[]'::jsonb,
  evidence_requirements jsonb not null default '[]'::jsonb,
  submission_checklist jsonb not null default '[]'::jsonb,
  instructions jsonb not null default '[]'::jsonb,
  field_mapping jsonb not null default '{}'::jsonb,
  user_instructions text not null default '',
  last_reviewed_at timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (administrator_name, template_version)
);

alter table public.administrator_templates
add column if not exists submission_checklist jsonb not null default '[]'::jsonb;

alter table public.administrator_templates
add column if not exists instructions jsonb not null default '[]'::jsonb;

create table if not exists public.claim_packets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  administrator_template_id uuid references public.administrator_templates(id) on delete set null,
  administrator_name text not null,
  status public.claim_packet_status not null default 'draft',
  submission_mode public.submission_mode not null default 'guided_packet',
  claim_amount numeric(12, 2) not null default 0 check (claim_amount >= 0),
  generated_pdf_bucket_id text,
  generated_pdf_object_path text,
  template_version text,
  submitted_at timestamptz,
  submission_method text check (
    submission_method is null
    or submission_method in ('administrator_portal', 'in_app', 'email', 'other')
  ),
  submission_confirmation_number text,
  submission_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.claim_packet_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  claim_packet_id uuid not null references public.claim_packets(id) on delete cascade,
  receipt_line_item_id uuid not null references public.receipt_line_items(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (claim_packet_id, receipt_line_item_id)
);

create table if not exists public.claim_packet_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  claim_packet_id uuid not null references public.claim_packets(id) on delete cascade,
  from_status public.claim_packet_status,
  to_status public.claim_packet_status not null,
  actor text not null check (actor in ('user', 'kai', 'system')),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tax_exports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tax_year integer not null,
  status public.tax_export_status not null default 'draft',
  total_medical_expenses numeric(12, 2) not null default 0 check (total_medical_expenses >= 0),
  csv_bucket_id text,
  csv_object_path text,
  pdf_bucket_id text,
  pdf_object_path text,
  generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null,
  entity_table text,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_source_connections_user_id on public.source_connections(user_id);
create index if not exists idx_receipts_user_id on public.receipts(user_id);
create index if not exists idx_receipts_status on public.receipts(status);
create index if not exists idx_receipt_files_user_id on public.receipt_files(user_id);
create index if not exists idx_receipt_files_receipt_id on public.receipt_files(receipt_id);
create index if not exists idx_receipt_line_items_user_id on public.receipt_line_items(user_id);
create index if not exists idx_receipt_line_items_receipt_id on public.receipt_line_items(receipt_id);
create index if not exists idx_classification_runs_user_id on public.classification_runs(user_id);
create index if not exists idx_classification_runs_receipt_id on public.classification_runs(receipt_id);
create index if not exists idx_claim_packets_user_id on public.claim_packets(user_id);
create index if not exists idx_claim_packets_administrator_template_id on public.claim_packets(administrator_template_id);
create index if not exists idx_claim_packet_items_user_id on public.claim_packet_items(user_id);
create index if not exists idx_claim_packet_items_packet_id on public.claim_packet_items(claim_packet_id);
create index if not exists idx_claim_packet_items_receipt_line_item_id on public.claim_packet_items(receipt_line_item_id);
create index if not exists idx_claim_packet_events_user_id on public.claim_packet_events(user_id);
create index if not exists idx_claim_packet_events_packet_id on public.claim_packet_events(claim_packet_id);
create index if not exists idx_tax_exports_user_year on public.tax_exports(user_id, tax_year);
create index if not exists idx_audit_events_user_id on public.audit_events(user_id);

alter table public.profiles enable row level security;
alter table public.mvp_progress_snapshots enable row level security;
alter table public.source_connections enable row level security;
alter table public.receipts enable row level security;
alter table public.receipt_files enable row level security;
alter table public.receipt_line_items enable row level security;
alter table public.classification_runs enable row level security;
alter table public.administrator_templates enable row level security;
alter table public.claim_packets enable row level security;
alter table public.claim_packet_items enable row level security;
alter table public.claim_packet_events enable row level security;
alter table public.tax_exports enable row level security;
alter table public.audit_events enable row level security;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles',
    'mvp_progress_snapshots',
    'source_connections',
    'receipts',
    'receipt_files',
    'receipt_line_items',
    'classification_runs',
    'claim_packets',
    'claim_packet_items',
    'claim_packet_events',
    'tax_exports',
    'audit_events'
  ]
  loop
    execute format('drop policy if exists "%1$s_select_own" on public.%1$I', table_name);
    execute format('drop policy if exists "%1$s_insert_own" on public.%1$I', table_name);
    execute format('drop policy if exists "%1$s_update_own" on public.%1$I', table_name);
    execute format('drop policy if exists "%1$s_delete_own" on public.%1$I', table_name);
    execute format('create policy "%1$s_select_own" on public.%1$I for select to authenticated using ((select auth.uid()) = user_id)', table_name);
    execute format('create policy "%1$s_insert_own" on public.%1$I for insert to authenticated with check ((select auth.uid()) = user_id)', table_name);
    execute format('create policy "%1$s_update_own" on public.%1$I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', table_name);
    execute format('create policy "%1$s_delete_own" on public.%1$I for delete to authenticated using ((select auth.uid()) = user_id)', table_name);
  end loop;
end $$;

drop policy if exists "administrator_templates_select_active" on public.administrator_templates;
create policy "administrator_templates_select_active"
on public.administrator_templates
for select
to authenticated
using (is_active = true);

grant select, insert, update, delete on
  public.profiles,
  public.mvp_progress_snapshots,
  public.source_connections,
  public.receipts,
  public.receipt_files,
  public.receipt_line_items,
  public.classification_runs,
  public.claim_packets,
  public.claim_packet_items,
  public.claim_packet_events,
  public.tax_exports,
  public.audit_events
to authenticated;
grant select on public.administrator_templates to authenticated;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();

drop trigger if exists mvp_progress_snapshots_set_updated_at on public.mvp_progress_snapshots;
create trigger mvp_progress_snapshots_set_updated_at before update on public.mvp_progress_snapshots for each row execute function public.set_updated_at();

drop trigger if exists source_connections_set_updated_at on public.source_connections;
create trigger source_connections_set_updated_at before update on public.source_connections for each row execute function public.set_updated_at();

drop trigger if exists receipts_set_updated_at on public.receipts;
create trigger receipts_set_updated_at before update on public.receipts for each row execute function public.set_updated_at();

drop trigger if exists receipt_files_set_updated_at on public.receipt_files;
create trigger receipt_files_set_updated_at before update on public.receipt_files for each row execute function public.set_updated_at();

drop trigger if exists receipt_line_items_set_updated_at on public.receipt_line_items;
create trigger receipt_line_items_set_updated_at before update on public.receipt_line_items for each row execute function public.set_updated_at();

drop trigger if exists classification_runs_set_updated_at on public.classification_runs;
create trigger classification_runs_set_updated_at before update on public.classification_runs for each row execute function public.set_updated_at();

drop trigger if exists administrator_templates_set_updated_at on public.administrator_templates;
create trigger administrator_templates_set_updated_at before update on public.administrator_templates for each row execute function public.set_updated_at();

insert into public.administrator_templates (
  administrator_name,
  template_version,
  supported_submission_mode,
  required_fields,
  evidence_requirements,
  submission_checklist,
  instructions,
  user_instructions,
  last_reviewed_at,
  is_active
)
values
  (
    'HealthEquity',
    '2026.1',
    'guided_packet',
    jsonb_build_array('Account holder name', 'Date of service', 'Provider or merchant', 'Claim amount'),
    jsonb_build_array(
      'Itemized receipt showing merchant, purchase date, eligible item, and amount',
      'Proof of payment when the receipt does not show a paid card transaction'
    ),
    jsonb_build_array(
      'Review the required claim fields before opening the administrator portal.',
      'Attach the generated SAVE claim packet PDF in HealthEquity.',
      'Return to SAVE and mark the packet submitted after upload.'
    ),
    jsonb_build_array('Submit through the HealthEquity member portal after reviewing the attached itemized evidence.'),
    'Submit through the HealthEquity member portal after reviewing the attached itemized evidence.',
    now(),
    true
  ),
  (
    'Inspira',
    '2026.1',
    'in_app_submission',
    jsonb_build_array('Participant name', 'Service date', 'Expense type', 'Claim amount'),
    jsonb_build_array(
      'Itemized receipt with merchant, date, item description, and amount',
      'Card transaction match or paid invoice'
    ),
    jsonb_build_array(
      'Review the required claim fields before starting the Inspira claim flow.',
      'Submit directly through Inspira when in-app submission is available.',
      'Return to SAVE and mark the packet submitted after confirmation.'
    ),
    jsonb_build_array('Use the Inspira claim flow when available; keep the guided packet as the fallback attachment.'),
    'Use the Inspira claim flow when available; keep the guided packet as the fallback attachment.',
    now(),
    true
  ),
  (
    'WEX',
    '2026.1',
    'guided_packet',
    jsonb_build_array('Employee name', 'Service date', 'Provider or store', 'Claim amount'),
    jsonb_build_array(
      'Itemized receipt or explanation of benefits',
      'Proof the user paid the expense'
    ),
    jsonb_build_array(
      'Review the required claim fields before opening WEX.',
      'Attach the generated SAVE claim packet PDF in the WEX benefits portal.',
      'Return to SAVE and mark the packet submitted after upload.'
    ),
    jsonb_build_array('Attach this packet in the WEX benefits portal and mark the claim submitted once uploaded.'),
    'Attach this packet in the WEX benefits portal and mark the claim submitted once uploaded.',
    now(),
    true
  )
on conflict (administrator_name, template_version) do update set
  supported_submission_mode = excluded.supported_submission_mode,
  required_fields = excluded.required_fields,
  evidence_requirements = excluded.evidence_requirements,
  submission_checklist = excluded.submission_checklist,
  instructions = excluded.instructions,
  user_instructions = excluded.user_instructions,
  last_reviewed_at = excluded.last_reviewed_at,
  is_active = excluded.is_active;

drop trigger if exists claim_packets_set_updated_at on public.claim_packets;
create trigger claim_packets_set_updated_at before update on public.claim_packets for each row execute function public.set_updated_at();

drop trigger if exists claim_packet_items_set_updated_at on public.claim_packet_items;
create trigger claim_packet_items_set_updated_at before update on public.claim_packet_items for each row execute function public.set_updated_at();

drop trigger if exists claim_packet_events_set_updated_at on public.claim_packet_events;
create trigger claim_packet_events_set_updated_at before update on public.claim_packet_events for each row execute function public.set_updated_at();

drop trigger if exists tax_exports_set_updated_at on public.tax_exports;
create trigger tax_exports_set_updated_at before update on public.tax_exports for each row execute function public.set_updated_at();

drop trigger if exists audit_events_set_updated_at on public.audit_events;
create trigger audit_events_set_updated_at before update on public.audit_events for each row execute function public.set_updated_at();

insert into storage.buckets (id, name, public)
values ('receipt-files', 'receipt-files', false)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('claim-packets', 'claim-packets', false)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('tax-exports', 'tax-exports', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "receipt_files_insert_own_path" on storage.objects;
create policy "receipt_files_insert_own_path"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'receipt-files'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "receipt_files_select_own_path" on storage.objects;
create policy "receipt_files_select_own_path"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'receipt-files'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "receipt_files_update_own_path" on storage.objects;
create policy "receipt_files_update_own_path"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'receipt-files'
  and (select auth.uid())::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'receipt-files'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "claim_packets_insert_own_path" on storage.objects;
create policy "claim_packets_insert_own_path"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'claim-packets'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "claim_packets_select_own_path" on storage.objects;
create policy "claim_packets_select_own_path"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'claim-packets'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "claim_packets_update_own_path" on storage.objects;
create policy "claim_packets_update_own_path"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'claim-packets'
  and (select auth.uid())::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'claim-packets'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "tax_exports_insert_own_path" on storage.objects;
create policy "tax_exports_insert_own_path"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'tax-exports'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "tax_exports_select_own_path" on storage.objects;
create policy "tax_exports_select_own_path"
on storage.objects
for select
to authenticated
using (
  bucket_id = 'tax-exports'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

drop policy if exists "tax_exports_update_own_path" on storage.objects;
create policy "tax_exports_update_own_path"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'tax-exports'
  and (select auth.uid())::text = (storage.foldername(name))[1]
)
with check (
  bucket_id = 'tax-exports'
  and (select auth.uid())::text = (storage.foldername(name))[1]
);

-- V1 security posture:
-- - The iOS app only uses authenticated user sessions.
-- - Supabase service_role keys are reserved for Edge Functions and server-side jobs.
-- - RLS policies never rely on user-editable auth metadata.
