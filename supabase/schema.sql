-- Schéma de la base du générateur de devis.
-- À exécuter une fois dans Supabase : SQL Editor > New query > coller ce fichier > Run.
-- Chaque utilisateur ne voit que ses propres données (Row Level Security).

-- Profils enregistrés : entreprises émettrices et clients.
create table if not exists public.profils (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  type text not null check (type in ('entreprise', 'client')),
  donnees jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- Devis. L'entreprise et le client sont copiés au moment de l'enregistrement,
-- pour que le document reste identique même si le profil change ensuite.
create table if not exists public.devis (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  numero text not null,
  date_devis date not null default current_date,
  valide_jusqu date,
  statut text not null default 'brouillon'
    check (statut in ('brouillon', 'envoye', 'accepte', 'refuse', 'facture')),
  entreprise jsonb not null default '{}',
  client jsonb not null default '{}',
  lignes jsonb not null default '[]',
  tva numeric not null default 20,
  notes text not null default '',
  total_ht numeric not null default 0,
  total_tva numeric not null default 0,
  total_ttc numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, numero)
);

-- Factures. Créées uniquement par convertir_devis_en_facture (numérotation
-- continue, sans trou) et non modifiables ensuite, sauf leur statut de paiement.
create table if not exists public.factures (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  devis_id uuid references public.devis on delete set null,
  devis_numero text,
  numero text not null,
  date_facture date not null,
  echeance date not null,
  statut text not null default 'emise' check (statut in ('emise', 'payee')),
  entreprise jsonb not null,
  client jsonb not null,
  lignes jsonb not null,
  tva numeric not null,
  notes text not null,
  total_ht numeric not null,
  total_tva numeric not null,
  total_ttc numeric not null,
  created_at timestamptz not null default now(),
  unique (user_id, numero)
);

-- Dernier numéro de facture attribué, par utilisateur et par année.
create table if not exists public.compteurs_factures (
  user_id uuid not null references auth.users on delete cascade,
  annee int not null,
  dernier int not null,
  primary key (user_id, annee)
);

alter table public.profils enable row level security;
alter table public.devis enable row level security;
alter table public.factures enable row level security;
alter table public.compteurs_factures enable row level security;

drop policy if exists "profils du propriétaire" on public.profils;
create policy "profils du propriétaire" on public.profils for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Un devis facturé ne peut plus être modifié ni supprimé.
drop policy if exists "lecture devis" on public.devis;
create policy "lecture devis" on public.devis for select to authenticated
  using (user_id = auth.uid());
drop policy if exists "ajout devis" on public.devis;
create policy "ajout devis" on public.devis for insert to authenticated
  with check (user_id = auth.uid() and statut <> 'facture');
drop policy if exists "modification devis" on public.devis;
create policy "modification devis" on public.devis for update to authenticated
  using (user_id = auth.uid() and statut <> 'facture')
  with check (user_id = auth.uid() and statut <> 'facture');
drop policy if exists "suppression devis" on public.devis;
create policy "suppression devis" on public.devis for delete to authenticated
  using (user_id = auth.uid() and statut <> 'facture');

drop policy if exists "lecture factures" on public.factures;
create policy "lecture factures" on public.factures for select to authenticated
  using (user_id = auth.uid());
drop policy if exists "statut factures" on public.factures;
create policy "statut factures" on public.factures for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Pas de création, de suppression ni de modification directe des factures
-- (seul le statut peut changer), ni d'accès direct aux compteurs.
revoke insert, update, delete, truncate on public.factures from anon, authenticated;
grant update (statut) on public.factures to authenticated;
revoke all on public.compteurs_factures from anon, authenticated;

-- Transforme un devis en facture : attribue le numéro suivant (F-2026-001…),
-- copie le devis dans la facture et passe le devis au statut « facture ».
create or replace function public.convertir_devis_en_facture(
  p_devis_id uuid,
  p_date date default current_date,
  p_echeance date default current_date + 30
) returns public.factures
language plpgsql
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  d public.devis;
  f public.factures;
  v_annee int := extract(year from p_date)::int;
  n int;
begin
  if uid is null then
    raise exception 'Connexion requise';
  end if;
  if p_echeance < p_date then
    raise exception 'La date d''échéance doit suivre la date de facture';
  end if;

  select * into d from public.devis where id = p_devis_id and user_id = uid for update;
  if not found then
    raise exception 'Devis introuvable';
  end if;
  if d.statut = 'facture' then
    raise exception 'Ce devis a déjà été facturé';
  end if;

  insert into public.compteurs_factures as c (user_id, annee, dernier)
  values (uid, v_annee, 1)
  on conflict (user_id, annee) do update set dernier = c.dernier + 1
  returning dernier into n;

  insert into public.factures (user_id, devis_id, devis_numero, numero, date_facture, echeance,
    entreprise, client, lignes, tva, notes, total_ht, total_tva, total_ttc)
  values (uid, d.id, d.numero, 'F-' || v_annee || '-' || lpad(n::text, 3, '0'), p_date, p_echeance,
    d.entreprise, d.client, d.lignes, d.tva, d.notes, d.total_ht, d.total_tva, d.total_ttc)
  returning * into f;

  update public.devis set statut = 'facture', updated_at = now() where id = d.id;
  return f;
end;
$$;

revoke execute on function public.convertir_devis_en_facture(uuid, date, date) from public, anon;
grant execute on function public.convertir_devis_en_facture(uuid, date, date) to authenticated;
