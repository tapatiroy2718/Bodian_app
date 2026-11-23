-- =====================================================================
-- BODIANA – complete Supabase database setup
-- Run this whole file once in Supabase → SQL Editor → New query → Run.
-- It is safe to re-run: objects are created with IF NOT EXISTS / OR REPLACE.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Helper functions
-- ---------------------------------------------------------------------

-- True when the statement runs as the database owner or the service-role
-- key (SQL editor, Edge Functions, or the verification operator).
-- Deliberately SECURITY INVOKER so current_user reflects the real caller.
create or replace function public.is_privileged()
returns boolean language sql stable as $$
  select current_user in ('postgres', 'supabase_admin', 'service_role');
$$;

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Users and roles
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        text check (role in ('customer', 'vendor')),
  full_name   text,
  email       text,
  phone       text,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid();
$$;

create table if not exists public.customer_profiles (
  user_id              uuid primary key references public.profiles(id) on delete cascade,
  wedding_city         text,
  wedding_location     text,
  wedding_date         date,
  budget               numeric(14,2),
  guest_count          integer check (guest_count is null or guest_count >= 0),
  planned_events       text[] not null default '{}',
  onboarding_completed boolean not null default false,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- New auth user → profile row. Role comes from sign-up metadata.
-- Google sign-ins have no role yet; the app then calls set_my_role().
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_role text := new.raw_user_meta_data ->> 'role';
begin
  if v_role is not null and v_role not in ('customer', 'vendor') then
    v_role := null;
  end if;

  insert into public.profiles (id, role, full_name, email, phone, avatar_url)
  values (
    new.id,
    v_role,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.email,
    nullif(new.raw_user_meta_data ->> 'phone', ''),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  if v_role = 'customer' then
    insert into public.customer_profiles (user_id) values (new.id) on conflict do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- A role can be chosen once and never changed (customer ≠ vendor).
create or replace function public.guard_profile()
returns trigger language plpgsql as $$
begin
  if new.id <> old.id then
    raise exception 'Profile id cannot be changed';
  end if;
  if old.role is not null and new.role is distinct from old.role and not public.is_privileged() then
    raise exception 'Account role cannot be changed';
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile();

create or replace function public.set_my_role(p_role text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_current text;
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  if p_role not in ('customer', 'vendor') then raise exception 'Invalid role'; end if;

  select role into v_current from public.profiles where id = auth.uid() for update;
  if not found then raise exception 'Profile not found'; end if;
  if v_current is not null then
    if v_current <> p_role then
      raise exception 'This account is already registered as a %', v_current;
    end if;
    return v_current;
  end if;

  update public.profiles set role = p_role where id = auth.uid();
  if p_role = 'customer' then
    insert into public.customer_profiles (user_id) values (auth.uid()) on conflict do nothing;
  end if;
  return p_role;
end $$;

drop trigger if exists customer_profiles_touch on public.customer_profiles;
create trigger customer_profiles_touch before update on public.customer_profiles
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Marketplace categories
-- ---------------------------------------------------------------------

create table if not exists public.service_categories (
  id            text primary key,
  name          text not null,
  subcategories text[] not null default '{}',
  sort          integer not null default 0
);

insert into public.service_categories (id, name, subcategories, sort) values
  ('venues',         'Venues',         array['Banquet', 'Marriage hall', 'Resort', 'Garden'], 1),
  ('catering',       'Catering',       array['Veg', 'Non-veg', 'Bengali cuisine'], 2),
  ('decoration',     'Decoration',     array['Stage', 'Flowers', 'Lighting', 'Entrance'], 3),
  ('photography',    'Photography',    array['Wedding photography', 'Pre-wedding'], 4),
  ('makeup',         'Makeup',         array['Bridal', 'Groom', 'Party makeup'], 5),
  ('mehendi',        'Mehendi',        array['Bridal mehendi', 'Guest mehendi'], 6),
  ('entertainment',  'Entertainment',  array['DJ', 'Music', 'Performers'], 7),
  ('planning',       'Planning',       array['Wedding planners', 'Coordinators'], 8),
  ('transportation', 'Transportation', array['Cars', 'Buses', 'Luxury vehicles'], 9),
  ('other',          'Other',          array['Florists', 'Invitations', 'Gifts', 'Priest'], 10)
on conflict (id) do update
  set name = excluded.name, subcategories = excluded.subcategories, sort = excluded.sort;

-- ---------------------------------------------------------------------
-- Vendors
-- ---------------------------------------------------------------------

create table if not exists public.vendor_profiles (
  id                  uuid primary key references public.profiles(id) on delete cascade,
  business_name       text not null check (length(trim(business_name)) > 0),
  category_id         text references public.service_categories(id),
  owner_name          text,
  address             text,
  city                text,
  description         text,
  phone               text,
  whatsapp            text,
  email               text,
  logo_url            text,
  cover_url           text,
  gallery             text[] not null default '{}',
  verification_status text not null default 'pending'
                      check (verification_status in ('pending', 'verified', 'rejected')),
  verification_note   text,
  verified_at         timestamptz,
  is_active           boolean not null default true,
  rating_avg          numeric(3,2) not null default 0,
  rating_count        integer not null default 0,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Vendors can never set their own verification status or ratings.
create or replace function public.guard_vendor_profile()
returns trigger language plpgsql as $$
begin
  if not public.is_privileged() then
    if tg_op = 'INSERT' then
      new.verification_status := 'pending';
      new.verification_note   := null;
      new.verified_at         := null;
      new.rating_avg          := 0;
      new.rating_count        := 0;
    else
      new.verification_status := old.verification_status;
      new.verification_note   := old.verification_note;
      new.verified_at         := old.verified_at;
      new.rating_avg          := old.rating_avg;
      new.rating_count        := old.rating_count;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists vendor_profiles_guard on public.vendor_profiles;
create trigger vendor_profiles_guard before insert or update on public.vendor_profiles
  for each row execute function public.guard_vendor_profile();

-- Public marketplace eligibility: verified and active.
create or replace function public.is_vendor_public(p_vendor uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.vendor_profiles v
    where v.id = p_vendor and v.verification_status = 'verified' and v.is_active
  );
$$;

create table if not exists public.vendor_documents (
  id          uuid primary key default gen_random_uuid(),
  vendor_id   uuid not null references public.vendor_profiles(id) on delete cascade,
  doc_type    text not null check (doc_type in ('trade_licence', 'business_registration', 'business_card', 'other')),
  file_path   text not null,
  file_name   text,
  mime_type   text,
  size_bytes  integer,
  uploaded_at timestamptz not null default now()
);

create table if not exists public.vendor_verifications (
  id          uuid primary key default gen_random_uuid(),
  vendor_id   uuid not null references public.vendor_profiles(id) on delete cascade,
  status      text not null check (status in ('pending', 'verified', 'rejected')),
  note        text,
  reviewed_by text,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Services, packages, venues, availability
-- ---------------------------------------------------------------------

create table if not exists public.services (
  id             uuid primary key default gen_random_uuid(),
  vendor_id      uuid not null references public.vendor_profiles(id) on delete cascade,
  category_id    text not null references public.service_categories(id),
  subcategory    text,
  title          text not null check (length(trim(title)) > 0),
  description    text,
  starting_price numeric(12,2) not null default 0 check (starting_price >= 0),
  city           text,
  location       text,
  facilities     text[] not null default '{}',
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists services_vendor_idx on public.services(vendor_id);
create index if not exists services_category_idx on public.services(category_id);

drop trigger if exists services_touch on public.services;
create trigger services_touch before update on public.services
  for each row execute function public.touch_updated_at();

create table if not exists public.service_images (
  id           uuid primary key default gen_random_uuid(),
  service_id   uuid not null references public.services(id) on delete cascade,
  url          text not null,
  storage_path text,
  sort         integer not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists service_images_service_idx on public.service_images(service_id);

create table if not exists public.service_packages (
  id                 uuid primary key default gen_random_uuid(),
  service_id         uuid not null references public.services(id) on delete cascade,
  name               text not null check (length(trim(name)) > 0),
  description        text,
  included_services  text[] not null default '{}',
  price              numeric(12,2) not null default 0 check (price >= 0),
  additional_charges text,
  terms              text,
  is_active          boolean not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists service_packages_service_idx on public.service_packages(service_id);

drop trigger if exists service_packages_touch on public.service_packages;
create trigger service_packages_touch before update on public.service_packages
  for each row execute function public.touch_updated_at();

create table if not exists public.venue_details (
  service_id           uuid primary key references public.services(id) on delete cascade,
  is_ac                boolean,
  min_guests           integer check (min_guests is null or min_guests >= 0),
  max_guests           integer check (max_guests is null or max_guests >= 0),
  seating              text,
  parking              boolean not null default false,
  catering_available   boolean not null default false,
  decoration_available boolean not null default false,
  indoor_outdoor       text check (indoor_outdoor is null or indoor_outdoor in ('indoor', 'outdoor', 'both')),
  latitude             double precision,
  longitude            double precision,
  map_address          text
);

create table if not exists public.vendor_availability (
  id         uuid primary key default gen_random_uuid(),
  vendor_id  uuid not null references public.vendor_profiles(id) on delete cascade,
  date       date not null,
  status     text not null check (status in ('available', 'unavailable', 'held')),
  note       text,
  created_at timestamptz not null default now(),
  unique (vendor_id, date)
);

-- ---------------------------------------------------------------------
-- Customer wedding planner
-- ---------------------------------------------------------------------

create table if not exists public.wedding_events (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  name        text not null check (length(trim(name)) > 0),
  event_date  date,
  location    text,
  notes       text,
  sort        integer not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists wedding_events_customer_idx on public.wedding_events(customer_id);

create table if not exists public.event_checklists (
  id               uuid primary key default gen_random_uuid(),
  event_id         uuid not null references public.wedding_events(id) on delete cascade,
  customer_id      uuid not null references public.profiles(id) on delete cascade,
  title            text not null check (length(trim(title)) > 0),
  category_id      text references public.service_categories(id),
  status           text not null default 'pending'
                   check (status in ('pending', 'done', 'not_done', 'skipped')),
  provider_name    text,
  provider_contact text,
  provider_notes   text,
  amount           numeric(14,2),
  sort             integer not null default 0,
  updated_at       timestamptz not null default now()
);
create index if not exists event_checklists_event_idx on public.event_checklists(event_id);

drop trigger if exists event_checklists_touch on public.event_checklists;
create trigger event_checklists_touch before update on public.event_checklists
  for each row execute function public.touch_updated_at();

create table if not exists public.checklist_templates (
  id          serial primary key,
  event_name  text not null,
  title       text not null,
  category_id text references public.service_categories(id),
  sort        integer not null default 0,
  unique (event_name, title)
);

insert into public.checklist_templates (event_name, title, category_id, sort) values
  ('Aiburo Bhat', 'Book venue', 'venues', 1),
  ('Aiburo Bhat', 'Arrange catering', 'catering', 2),
  ('Aiburo Bhat', 'Book photographer', 'photography', 3),
  ('Aiburo Bhat', 'Arrange decoration', 'decoration', 4),
  ('Ashirbad', 'Arrange venue', 'venues', 1),
  ('Ashirbad', 'Arrange catering', 'catering', 2),
  ('Ashirbad', 'Book photographer', 'photography', 3),
  ('Ashirbad', 'Arrange gifts and tattva', 'other', 4),
  ('Engagement', 'Book venue', 'venues', 1),
  ('Engagement', 'Arrange catering', 'catering', 2),
  ('Engagement', 'Arrange decoration', 'decoration', 3),
  ('Engagement', 'Book photographer', 'photography', 4),
  ('Engagement', 'Book makeup artist', 'makeup', 5),
  ('Engagement', 'Buy rings', 'other', 6),
  ('Mehendi', 'Book mehendi artist', 'mehendi', 1),
  ('Mehendi', 'Arrange decoration', 'decoration', 2),
  ('Mehendi', 'Arrange music / DJ', 'entertainment', 3),
  ('Mehendi', 'Book photographer', 'photography', 4),
  ('Gaye Holud', 'Arrange turmeric and tattva', 'other', 1),
  ('Gaye Holud', 'Arrange decoration', 'decoration', 2),
  ('Gaye Holud', 'Book photographer', 'photography', 3),
  ('Gaye Holud', 'Book makeup artist', 'makeup', 4),
  ('Biye', 'Book venue', 'venues', 1),
  ('Biye', 'Arrange catering', 'catering', 2),
  ('Biye', 'Arrange decoration', 'decoration', 3),
  ('Biye', 'Book photographer', 'photography', 4),
  ('Biye', 'Bridal makeup', 'makeup', 5),
  ('Biye', 'Groom makeup', 'makeup', 6),
  ('Biye', 'Book priest (purohit)', 'other', 7),
  ('Biye', 'Arrange transportation', 'transportation', 8),
  ('Biye', 'Arrange music / shehnai', 'entertainment', 9),
  ('Biye', 'Send invitations', 'other', 10),
  ('Bou Bhat', 'Book venue', 'venues', 1),
  ('Bou Bhat', 'Arrange catering', 'catering', 2),
  ('Bou Bhat', 'Arrange decoration', 'decoration', 3),
  ('Bou Bhat', 'Book photographer', 'photography', 4),
  ('Bou Bhat', 'Bridal makeup', 'makeup', 5),
  ('Reception', 'Book venue', 'venues', 1),
  ('Reception', 'Arrange catering', 'catering', 2),
  ('Reception', 'Arrange decoration', 'decoration', 3),
  ('Reception', 'Book photographer', 'photography', 4),
  ('Reception', 'Book makeup artist', 'makeup', 5),
  ('Reception', 'Book DJ / entertainment', 'entertainment', 6),
  ('Reception', 'Arrange transportation', 'transportation', 7),
  ('default', 'Book venue', 'venues', 1),
  ('default', 'Arrange catering', 'catering', 2),
  ('default', 'Arrange decoration', 'decoration', 3),
  ('default', 'Book photographer', 'photography', 4)
on conflict (event_name, title) do nothing;

-- Adds one event with its default checklist. Runs with the caller's
-- permissions, so RLS still applies.
create or replace function public.add_wedding_event(p_name text, p_date date default null, p_location text default null)
returns uuid language plpgsql set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_event uuid;
  v_key   text;
  v_sort  integer;
begin
  if v_uid is null then raise exception 'Please sign in first'; end if;
  if public.my_role() is distinct from 'customer' then raise exception 'Only customers can plan events'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'Event name is required'; end if;

  select coalesce(max(sort), 0) + 1 into v_sort from public.wedding_events where customer_id = v_uid;

  insert into public.wedding_events (customer_id, name, event_date, location, sort)
  values (v_uid, trim(p_name), p_date, p_location, v_sort)
  returning id into v_event;

  v_key := case when exists (select 1 from public.checklist_templates where event_name = trim(p_name))
                then trim(p_name) else 'default' end;

  insert into public.event_checklists (event_id, customer_id, title, category_id, sort)
  select v_event, v_uid, t.title, t.category_id, t.sort
  from public.checklist_templates t where t.event_name = v_key;

  return v_event;
end $$;

-- Creates the events chosen during onboarding (skips ones that already exist).
create or replace function public.create_wedding_plan(p_events text[])
returns integer language plpgsql set search_path = public as $$
declare
  v_name  text;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  foreach v_name in array coalesce(p_events, '{}') loop
    if not exists (select 1 from public.wedding_events
                   where customer_id = auth.uid() and lower(name) = lower(trim(v_name))) then
      perform public.add_wedding_event(v_name);
      v_count := v_count + 1;
    end if;
  end loop;
  return v_count;
end $$;

create table if not exists public.wishlist (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id) on delete cascade,
  service_id  uuid not null references public.services(id) on delete cascade,
  created_at  timestamptz not null default now(),
  unique (customer_id, service_id)
);

-- ---------------------------------------------------------------------
-- Bookings, reviews, notifications
-- ---------------------------------------------------------------------

create table if not exists public.bookings (
  id             uuid primary key default gen_random_uuid(),
  customer_id    uuid not null references public.profiles(id) on delete cascade,
  vendor_id      uuid not null references public.vendor_profiles(id) on delete cascade,
  service_id     uuid references public.services(id) on delete set null,
  package_id     uuid references public.service_packages(id) on delete set null,
  service_title  text,
  package_name   text,
  package_price  numeric(12,2),
  event_type     text,
  event_date     date not null,
  guest_count    integer check (guest_count is null or guest_count >= 0),
  customer_name  text,
  customer_phone text,
  requirements   text,
  message        text,
  status         text not null default 'pending'
                 check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'completed')),
  status_reason  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists bookings_customer_idx on public.bookings(customer_id);
create index if not exists bookings_vendor_idx on public.bookings(vendor_id);
-- One confirmed booking per service per date (prevents double booking).
create unique index if not exists bookings_no_double_booking
  on public.bookings(service_id, event_date) where status in ('accepted', 'completed');

create table if not exists public.booking_status_history (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null references public.bookings(id) on delete cascade,
  from_status text,
  to_status   text not null,
  reason      text,
  changed_by  uuid,
  actor_role  text,
  created_at  timestamptz not null default now()
);
create index if not exists booking_history_booking_idx on public.booking_status_history(booking_id);

create table if not exists public.reviews (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid not null unique references public.bookings(id) on delete cascade,
  customer_id   uuid not null references public.profiles(id) on delete cascade,
  vendor_id     uuid not null references public.vendor_profiles(id) on delete cascade,
  service_id    uuid references public.services(id) on delete set null,
  customer_name text,
  rating        integer not null check (rating between 1 and 5),
  comment       text,
  created_at    timestamptz not null default now()
);
create index if not exists reviews_vendor_idx on public.reviews(vendor_id);

create table if not exists public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles(id) on delete cascade,
  title      text not null,
  body       text,
  type       text not null default 'general',
  booking_id uuid references public.bookings(id) on delete set null,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);

create or replace function public.notify(p_user uuid, p_title text, p_body text, p_type text, p_booking uuid)
returns void language sql security definer set search_path = public as $$
  insert into public.notifications (user_id, title, body, type, booking_id)
  values (p_user, p_title, p_body, p_type, p_booking);
$$;

-- Customer sends a booking request.
create or replace function public.create_booking(
  p_service_id     uuid,
  p_event_date     date,
  p_package_id     uuid default null,
  p_event_type     text default null,
  p_guest_count    integer default null,
  p_customer_name  text default null,
  p_customer_phone text default null,
  p_requirements   text default null,
  p_message        text default null
) returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid     uuid := auth.uid();
  v_service public.services%rowtype;
  v_vendor  public.vendor_profiles%rowtype;
  v_package public.service_packages%rowtype;
  v_id      uuid;
begin
  if v_uid is null then raise exception 'Please sign in first'; end if;
  if public.my_role() is distinct from 'customer' then raise exception 'Only customer accounts can send booking requests'; end if;
  if p_event_date is null or p_event_date < current_date then raise exception 'Please choose a future event date'; end if;
  if p_guest_count is not null and p_guest_count < 0 then raise exception 'Guest count cannot be negative'; end if;

  select * into v_service from public.services where id = p_service_id;
  if not found or not v_service.is_active then raise exception 'This service is not available for booking'; end if;

  select * into v_vendor from public.vendor_profiles where id = v_service.vendor_id;
  if v_vendor.verification_status <> 'verified' or not v_vendor.is_active then
    raise exception 'This vendor is not accepting bookings right now';
  end if;

  if p_package_id is not null then
    select * into v_package from public.service_packages
     where id = p_package_id and service_id = p_service_id and is_active;
    if not found then raise exception 'The selected package is not available'; end if;
  end if;

  if exists (select 1 from public.bookings where service_id = p_service_id and event_date = p_event_date
             and status in ('accepted', 'completed')) then
    raise exception 'This service is already booked on %', to_char(p_event_date, 'DD Mon YYYY');
  end if;
  if exists (select 1 from public.vendor_availability where vendor_id = v_vendor.id
             and date = p_event_date and status = 'unavailable') then
    raise exception 'The vendor is unavailable on %', to_char(p_event_date, 'DD Mon YYYY');
  end if;
  if exists (select 1 from public.bookings where customer_id = v_uid and service_id = p_service_id
             and event_date = p_event_date and status in ('pending', 'accepted')) then
    raise exception 'You already have an active request for this service on that date';
  end if;

  insert into public.bookings (customer_id, vendor_id, service_id, package_id, service_title, package_name,
                               package_price, event_type, event_date, guest_count, customer_name,
                               customer_phone, requirements, message)
  values (v_uid, v_vendor.id, p_service_id, p_package_id, v_service.title, v_package.name,
          v_package.price, p_event_type, p_event_date, p_guest_count,
          coalesce(nullif(trim(p_customer_name), ''), (select full_name from public.profiles where id = v_uid)),
          nullif(trim(p_customer_phone), ''), p_requirements, p_message)
  returning id into v_id;

  insert into public.booking_status_history (booking_id, from_status, to_status, changed_by, actor_role)
  values (v_id, null, 'pending', v_uid, 'customer');

  perform public.notify(v_vendor.id, 'New booking request',
    coalesce(p_event_type, 'Event') || ' on ' || to_char(p_event_date, 'DD Mon YYYY') || ' for ' || v_service.title,
    'booking_new', v_id);
  return v_id;
end $$;

-- Status changes by either party, with the allowed transitions enforced.
create or replace function public.update_booking_status(p_booking_id uuid, p_status text, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_uid   uuid := auth.uid();
  v_b     public.bookings%rowtype;
  v_actor text;
  v_ok    boolean := false;
  v_date  text;
begin
  if v_uid is null then raise exception 'Please sign in first'; end if;
  select * into v_b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;

  if v_b.customer_id = v_uid then v_actor := 'customer';
  elsif v_b.vendor_id = v_uid then v_actor := 'vendor';
  else raise exception 'You do not have access to this booking';
  end if;

  if v_actor = 'customer' then
    v_ok := p_status = 'cancelled' and v_b.status in ('pending', 'accepted');
  else
    v_ok := (v_b.status = 'pending'  and p_status in ('accepted', 'rejected'))
         or (v_b.status = 'accepted' and p_status in ('cancelled', 'completed'));
  end if;
  if not v_ok then
    raise exception 'A % booking cannot be changed to % by the %', v_b.status, p_status, v_actor;
  end if;

  if p_status in ('rejected', 'cancelled') and v_actor = 'vendor' and coalesce(trim(p_reason), '') = '' then
    raise exception 'Please give a reason';
  end if;

  if p_status = 'accepted' and exists (
      select 1 from public.bookings where service_id = v_b.service_id and event_date = v_b.event_date
        and status in ('accepted', 'completed') and id <> v_b.id) then
    raise exception 'You already have a confirmed booking for this service on this date';
  end if;

  update public.bookings
     set status = p_status, status_reason = nullif(trim(p_reason), ''), updated_at = now()
   where id = v_b.id;

  insert into public.booking_status_history (booking_id, from_status, to_status, reason, changed_by, actor_role)
  values (v_b.id, v_b.status, p_status, nullif(trim(p_reason), ''), v_uid, v_actor);

  v_date := to_char(v_b.event_date, 'DD Mon YYYY');
  if p_status = 'accepted' then
    perform public.notify(v_b.customer_id, 'Booking accepted',
      coalesce(v_b.service_title, 'Your booking') || ' on ' || v_date || ' is confirmed.', 'booking_accepted', v_b.id);
  elsif p_status = 'rejected' then
    perform public.notify(v_b.customer_id, 'Booking request declined',
      coalesce(v_b.service_title, 'Your request') || ' on ' || v_date || coalesce(': ' || nullif(trim(p_reason), ''), ''),
      'booking_rejected', v_b.id);
  elsif p_status = 'cancelled' then
    perform public.notify(case when v_actor = 'customer' then v_b.vendor_id else v_b.customer_id end,
      'Booking cancelled',
      coalesce(v_b.service_title, 'A booking') || ' on ' || v_date || ' was cancelled by the ' || v_actor
        || coalesce(': ' || nullif(trim(p_reason), ''), ''),
      'booking_cancelled', v_b.id);
  elsif p_status = 'completed' then
    perform public.notify(v_b.customer_id, 'Booking completed',
      'How was ' || coalesce(v_b.service_title, 'the service') || '? You can now leave a review.', 'booking_completed', v_b.id);
    perform public.notify(v_b.vendor_id, 'Booking completed',
      coalesce(v_b.service_title, 'Booking') || ' on ' || v_date || ' was marked completed.', 'booking_completed', v_b.id);
  end if;
end $$;

-- Customer reviews a completed booking (one review per booking).
create or replace function public.submit_review(p_booking_id uuid, p_rating integer, p_comment text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_b   public.bookings%rowtype;
  v_id  uuid;
begin
  if v_uid is null then raise exception 'Please sign in first'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'Rating must be between 1 and 5'; end if;
  select * into v_b from public.bookings where id = p_booking_id;
  if not found or v_b.customer_id <> v_uid then raise exception 'Booking not found'; end if;
  if v_b.status <> 'completed' then raise exception 'You can review a booking only after it is completed'; end if;
  if exists (select 1 from public.reviews where booking_id = p_booking_id) then
    raise exception 'You have already reviewed this booking';
  end if;

  insert into public.reviews (booking_id, customer_id, vendor_id, service_id, customer_name, rating, comment)
  values (v_b.id, v_uid, v_b.vendor_id, v_b.service_id,
          coalesce(v_b.customer_name, (select full_name from public.profiles where id = v_uid)),
          p_rating, nullif(trim(p_comment), ''))
  returning id into v_id;

  update public.vendor_profiles v set
    rating_avg   = coalesce((select round(avg(rating)::numeric, 2) from public.reviews r where r.vendor_id = v.id), 0),
    rating_count = (select count(*) from public.reviews r where r.vendor_id = v.id)
  where v.id = v_b.vendor_id;

  perform public.notify(v_b.vendor_id, 'New review',
    p_rating || '★ review for ' || coalesce(v_b.service_title, 'your service'), 'review_new', v_b.id);
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- Vendor verification
-- ---------------------------------------------------------------------

-- Vendor asks for another review after a rejection (or after adding documents).
create or replace function public.request_verification_review()
returns text language plpgsql security definer set search_path = public as $$
declare
  v_status text;
begin
  select verification_status into v_status from public.vendor_profiles where id = auth.uid();
  if not found then raise exception 'Create your business profile first'; end if;
  if v_status = 'verified' then return v_status; end if;
  update public.vendor_profiles set verification_status = 'pending', verification_note = null where id = auth.uid();
  insert into public.vendor_verifications (vendor_id, status, note, reviewed_by)
  values (auth.uid(), 'pending', 'Review requested by vendor', null);
  return 'pending';
end $$;

-- OPERATOR ONLY. Run from the Supabase SQL editor, e.g.
--   select public.admin_review_vendor('<vendor uuid>', 'verified', null, 'ops@bodiana');
--   select public.admin_review_vendor('<vendor uuid>', 'rejected', 'Trade licence is unreadable', 'ops@bodiana');
create or replace function public.admin_review_vendor(p_vendor uuid, p_decision text, p_note text default null, p_reviewer text default 'operator')
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_decision not in ('verified', 'rejected', 'pending') then raise exception 'Decision must be verified, rejected or pending'; end if;
  if p_decision = 'rejected' and coalesce(trim(p_note), '') = '' then raise exception 'A rejection needs a reason'; end if;

  update public.vendor_profiles
     set verification_status = p_decision,
         verification_note   = nullif(trim(p_note), ''),
         verified_at         = case when p_decision = 'verified' then now() else null end
   where id = p_vendor;
  if not found then raise exception 'Vendor not found'; end if;

  insert into public.vendor_verifications (vendor_id, status, note, reviewed_by)
  values (p_vendor, p_decision, nullif(trim(p_note), ''), p_reviewer);

  perform public.notify(p_vendor, 'Verification updated',
    case p_decision
      when 'verified' then 'Your business is verified and now visible to customers.'
      when 'rejected' then 'Verification was not approved: ' || p_note
      else 'Your verification is pending review.' end,
    'verification', null);
end $$;

-- Handy operator view of vendors waiting for review (not exposed to the app).
create or replace view public.admin_pending_vendors with (security_invoker = true) as
  select v.id, v.business_name, v.category_id, v.city, v.phone, p.email, v.created_at,
         (select count(*) from public.vendor_documents d where d.vendor_id = v.id) as documents
  from public.vendor_profiles v join public.profiles p on p.id = v.id
  where v.verification_status = 'pending'
  order by v.created_at;

-- ---------------------------------------------------------------------
-- Marketplace search
-- ---------------------------------------------------------------------

create or replace function public.search_services(
  p_category   text    default null,
  p_query      text    default null,
  p_city       text    default null,
  p_min_price  numeric default null,
  p_max_price  numeric default null,
  p_min_rating numeric default null,
  p_guests     integer default null,
  p_is_ac      boolean default null,
  p_date       date    default null,
  p_sort       text    default 'recommended',
  p_limit      integer default 60
) returns table (id uuid)
language sql stable security definer set search_path = public as $$
  select s.id
  from public.services s
  join public.vendor_profiles v on v.id = s.vendor_id
  left join public.venue_details vd on vd.service_id = s.id
  where s.is_active and v.is_active and v.verification_status = 'verified'
    and (p_category is null or s.category_id = p_category)
    and (nullif(trim(p_query), '') is null
         or s.title ilike '%' || trim(p_query) || '%'
         or v.business_name ilike '%' || trim(p_query) || '%'
         or coalesce(s.subcategory, '') ilike '%' || trim(p_query) || '%'
         or coalesce(s.description, '') ilike '%' || trim(p_query) || '%')
    and (nullif(trim(p_city), '') is null
         or coalesce(s.city, '') ilike '%' || trim(p_city) || '%'
         or coalesce(v.city, '') ilike '%' || trim(p_city) || '%'
         or coalesce(s.location, '') ilike '%' || trim(p_city) || '%')
    and (p_min_price is null or s.starting_price >= p_min_price)
    and (p_max_price is null or s.starting_price <= p_max_price)
    and (p_min_rating is null or v.rating_avg >= p_min_rating)
    and (p_guests is null
         or (vd.service_id is not null and coalesce(vd.max_guests, 0) >= p_guests)
         or (vd.service_id is null and s.category_id <> 'venues'))
    and (p_is_ac is null or vd.is_ac = p_is_ac)
    and (p_date is null or (
          not exists (select 1 from public.bookings b where b.service_id = s.id and b.event_date = p_date
                      and b.status in ('accepted', 'completed'))
          and not exists (select 1 from public.vendor_availability a where a.vendor_id = s.vendor_id
                          and a.date = p_date and a.status = 'unavailable')))
  order by
    case when p_sort = 'price_low'  then s.starting_price end asc nulls last,
    case when p_sort = 'price_high' then s.starting_price end desc nulls last,
    case when p_sort = 'rating'     then v.rating_avg end desc nulls last,
    v.rating_count desc, v.rating_avg desc, s.created_at desc
  limit greatest(1, least(coalesce(p_limit, 60), 200));
$$;

-- Dates a public service cannot be booked (confirmed bookings + vendor blocks).
create or replace function public.service_unavailable_dates(p_service_id uuid)
returns table (date date, reason text)
language sql stable security definer set search_path = public as $$
  select b.event_date, 'booked'
    from public.bookings b
    join public.services s on s.id = b.service_id
   where b.service_id = p_service_id and b.status in ('accepted', 'completed')
     and b.event_date >= current_date
     and (public.is_vendor_public(s.vendor_id) or s.vendor_id = auth.uid())
  union
  select a.date, 'unavailable'
    from public.vendor_availability a
    join public.services s on s.vendor_id = a.vendor_id
   where s.id = p_service_id and a.status = 'unavailable' and a.date >= current_date
     and (public.is_vendor_public(s.vendor_id) or s.vendor_id = auth.uid())
  order by 1;
$$;

-- ---------------------------------------------------------------------
-- Account deletion (required by Google Play for apps with accounts)
-- ---------------------------------------------------------------------

create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Please sign in first'; end if;
  if exists (select 1 from public.bookings
             where (customer_id = v_uid or vendor_id = v_uid) and status = 'accepted' and event_date >= current_date) then
    raise exception 'You have upcoming confirmed bookings. Cancel them before deleting your account.';
  end if;
  delete from auth.users where id = v_uid;
end $$;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------

alter table public.profiles               enable row level security;
alter table public.customer_profiles      enable row level security;
alter table public.service_categories     enable row level security;
alter table public.vendor_profiles        enable row level security;
alter table public.vendor_documents       enable row level security;
alter table public.vendor_verifications   enable row level security;
alter table public.services               enable row level security;
alter table public.service_images         enable row level security;
alter table public.service_packages       enable row level security;
alter table public.venue_details          enable row level security;
alter table public.vendor_availability    enable row level security;
alter table public.wedding_events         enable row level security;
alter table public.event_checklists       enable row level security;
alter table public.checklist_templates    enable row level security;
alter table public.wishlist               enable row level security;
alter table public.bookings               enable row level security;
alter table public.booking_status_history enable row level security;
alter table public.reviews                enable row level security;
alter table public.notifications          enable row level security;

-- profiles
drop policy if exists "profiles: own read" on public.profiles;
create policy "profiles: own read" on public.profiles for select to authenticated using (id = auth.uid());
drop policy if exists "profiles: own update" on public.profiles;
create policy "profiles: own update" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- customer_profiles
drop policy if exists "customer_profiles: own" on public.customer_profiles;
create policy "customer_profiles: own" on public.customer_profiles for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid() and public.my_role() = 'customer');

-- reference data
drop policy if exists "categories: read" on public.service_categories;
create policy "categories: read" on public.service_categories for select to anon, authenticated using (true);
drop policy if exists "templates: read" on public.checklist_templates;
create policy "templates: read" on public.checklist_templates for select to authenticated using (true);

-- vendor_profiles
drop policy if exists "vendor_profiles: read" on public.vendor_profiles;
create policy "vendor_profiles: read" on public.vendor_profiles for select to authenticated
  using (id = auth.uid()
         or (verification_status = 'verified' and is_active)
         or exists (select 1 from public.bookings b where b.vendor_id = vendor_profiles.id and b.customer_id = auth.uid()));
drop policy if exists "vendor_profiles: insert own" on public.vendor_profiles;
create policy "vendor_profiles: insert own" on public.vendor_profiles for insert to authenticated
  with check (id = auth.uid() and public.my_role() = 'vendor');
drop policy if exists "vendor_profiles: update own" on public.vendor_profiles;
create policy "vendor_profiles: update own" on public.vendor_profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- vendor_documents (private to the vendor; operators use the SQL editor / dashboard)
drop policy if exists "vendor_documents: own read" on public.vendor_documents;
create policy "vendor_documents: own read" on public.vendor_documents for select to authenticated
  using (vendor_id = auth.uid());
drop policy if exists "vendor_documents: own insert" on public.vendor_documents;
create policy "vendor_documents: own insert" on public.vendor_documents for insert to authenticated
  with check (vendor_id = auth.uid() and file_path like auth.uid()::text || '/%');
drop policy if exists "vendor_documents: own delete" on public.vendor_documents;
create policy "vendor_documents: own delete" on public.vendor_documents for delete to authenticated
  using (vendor_id = auth.uid());

drop policy if exists "vendor_verifications: own read" on public.vendor_verifications;
create policy "vendor_verifications: own read" on public.vendor_verifications for select to authenticated
  using (vendor_id = auth.uid());

-- services
drop policy if exists "services: read" on public.services;
create policy "services: read" on public.services for select to authenticated
  using (vendor_id = auth.uid()
         or (is_active and public.is_vendor_public(vendor_id))
         or exists (select 1 from public.bookings b where b.service_id = services.id and b.customer_id = auth.uid()));
drop policy if exists "services: vendor insert" on public.services;
create policy "services: vendor insert" on public.services for insert to authenticated
  with check (vendor_id = auth.uid());
drop policy if exists "services: vendor update" on public.services;
create policy "services: vendor update" on public.services for update to authenticated
  using (vendor_id = auth.uid()) with check (vendor_id = auth.uid());
drop policy if exists "services: vendor delete" on public.services;
create policy "services: vendor delete" on public.services for delete to authenticated
  using (vendor_id = auth.uid());

-- service children: visible when the parent service is visible; writable by its vendor
drop policy if exists "service_images: read" on public.service_images;
create policy "service_images: read" on public.service_images for select to authenticated
  using (exists (select 1 from public.services s where s.id = service_id));
drop policy if exists "service_images: vendor write" on public.service_images;
create policy "service_images: vendor write" on public.service_images for all to authenticated
  using (exists (select 1 from public.services s where s.id = service_id and s.vendor_id = auth.uid()))
  with check (exists (select 1 from public.services s where s.id = service_id and s.vendor_id = auth.uid()));

drop policy if exists "service_packages: read" on public.service_packages;
create policy "service_packages: read" on public.service_packages for select to authenticated
  using (exists (select 1 from public.services s where s.id = service_id));
drop policy if exists "service_packages: vendor write" on public.service_packages;
create policy "service_packages: vendor write" on public.service_packages for all to authenticated
  using (exists (select 1 from public.services s where s.id = service_id and s.vendor_id = auth.uid()))
  with check (exists (select 1 from public.services s where s.id = service_id and s.vendor_id = auth.uid()));

drop policy if exists "venue_details: read" on public.venue_details;
create policy "venue_details: read" on public.venue_details for select to authenticated
  using (exists (select 1 from public.services s where s.id = service_id));
drop policy if exists "venue_details: vendor write" on public.venue_details;
create policy "venue_details: vendor write" on public.venue_details for all to authenticated
  using (exists (select 1 from public.services s where s.id = service_id and s.vendor_id = auth.uid()))
  with check (exists (select 1 from public.services s where s.id = service_id and s.vendor_id = auth.uid()));

-- availability
drop policy if exists "availability: read" on public.vendor_availability;
create policy "availability: read" on public.vendor_availability for select to authenticated
  using (vendor_id = auth.uid() or public.is_vendor_public(vendor_id));
drop policy if exists "availability: vendor write" on public.vendor_availability;
create policy "availability: vendor write" on public.vendor_availability for all to authenticated
  using (vendor_id = auth.uid()) with check (vendor_id = auth.uid());

-- planner
drop policy if exists "wedding_events: own" on public.wedding_events;
create policy "wedding_events: own" on public.wedding_events for all to authenticated
  using (customer_id = auth.uid()) with check (customer_id = auth.uid() and public.my_role() = 'customer');

drop policy if exists "event_checklists: own" on public.event_checklists;
create policy "event_checklists: own" on public.event_checklists for all to authenticated
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid()
              and exists (select 1 from public.wedding_events e where e.id = event_id and e.customer_id = auth.uid()));

drop policy if exists "wishlist: own" on public.wishlist;
create policy "wishlist: own" on public.wishlist for all to authenticated
  using (customer_id = auth.uid()) with check (customer_id = auth.uid() and public.my_role() = 'customer');

-- bookings: read by the two parties only; all writes go through the functions above
drop policy if exists "bookings: parties read" on public.bookings;
create policy "bookings: parties read" on public.bookings for select to authenticated
  using (customer_id = auth.uid() or vendor_id = auth.uid());

drop policy if exists "booking_history: parties read" on public.booking_status_history;
create policy "booking_history: parties read" on public.booking_status_history for select to authenticated
  using (exists (select 1 from public.bookings b where b.id = booking_id
                 and (b.customer_id = auth.uid() or b.vendor_id = auth.uid())));

drop policy if exists "reviews: read" on public.reviews;
create policy "reviews: read" on public.reviews for select to authenticated using (true);

drop policy if exists "notifications: own read" on public.notifications;
create policy "notifications: own read" on public.notifications for select to authenticated
  using (user_id = auth.uid());
drop policy if exists "notifications: own update" on public.notifications;
create policy "notifications: own update" on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "notifications: own delete" on public.notifications;
create policy "notifications: own delete" on public.notifications for delete to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Function permissions
-- ---------------------------------------------------------------------

revoke execute on function public.admin_review_vendor(uuid, text, text, text) from public, anon, authenticated;
revoke execute on function public.notify(uuid, text, text, text, uuid) from public, anon, authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke all on public.admin_pending_vendors from anon, authenticated;

-- ---------------------------------------------------------------------
-- Storage buckets and policies
--   public-media      → logos, covers, gallery, service photos (public URLs)
--   vendor-documents  → verification documents (private, owner only)
-- Files must be stored under a folder named after the user's id.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('public-media', 'public-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('vendor-documents', 'vendor-documents', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "bodiana public-media read" on storage.objects;
create policy "bodiana public-media read" on storage.objects for select to anon, authenticated
  using (bucket_id = 'public-media');
drop policy if exists "bodiana public-media insert own" on storage.objects;
create policy "bodiana public-media insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'public-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "bodiana public-media update own" on storage.objects;
create policy "bodiana public-media update own" on storage.objects for update to authenticated
  using (bucket_id = 'public-media' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "bodiana public-media delete own" on storage.objects;
create policy "bodiana public-media delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'public-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "bodiana documents read own" on storage.objects;
create policy "bodiana documents read own" on storage.objects for select to authenticated
  using (bucket_id = 'vendor-documents' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "bodiana documents insert own" on storage.objects;
create policy "bodiana documents insert own" on storage.objects for insert to authenticated
  with check (bucket_id = 'vendor-documents' and (storage.foldername(name))[1] = auth.uid()::text
              and public.my_role() = 'vendor');
drop policy if exists "bodiana documents delete own" on storage.objects;
create policy "bodiana documents delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'vendor-documents' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------------------------------------------------------------------
-- Realtime (live booking and notification updates)
-- ---------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                   and schemaname = 'public' and tablename = 'notifications') then
      alter publication supabase_realtime add table public.notifications;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                   and schemaname = 'public' and tablename = 'bookings') then
      alter publication supabase_realtime add table public.bookings;
    end if;
  end if;
end $$;
