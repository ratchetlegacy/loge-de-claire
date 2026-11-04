-- La Loge de Claire : séance photo (costumes « à compléter »)
alter table public.loge_costumes add column if not exists brouillon boolean not null default false;

create or replace function public.loge_univers_liste() returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'label',u.label,'bg',u.bg,
    'nb',(select count(*) from loge_costumes c where c.univers=u.id and c.actif and not c.brouillon),
    'photo',(select c.photo from loge_costumes c where c.univers=u.id and c.actif and not c.brouillon and c.photo is not null order by c.id limit 1)) order by u.ordre,u.label),'[]'::jsonb)
  from loge_univers u;
$$;
create or replace function public.loge_catalogue(p_univers text) returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nom',c.nom,'univers',c.univers,'descr',c.descr,'photo',c.photo,'tailles',loge_tailles(c.id,c.tailles)) order by c.photo is null, c.nom),'[]'::jsonb)
  from loge_costumes c where c.actif and not c.brouillon and c.univers=p_univers;
$$;
create or replace function public.loge_top(p_n int default 5) returns jsonb language sql stable security definer set search_path=public as $$
  with sc as (
    select (f->>'id')::bigint id, 1 pts from loge_rdv r, jsonb_array_elements(r.favoris) f where r.cree>now()-interval '12 months' and (f->>'id') ~ '^[0-9]+$'
    union all select costume_id, 2 from loge_locations where costume_id is not null and cree>now()-interval '12 months'),
  t as (select id, sum(pts) s from sc group by id)
  select coalesce(jsonb_agg(x order by x->>'rang'),'[]'::jsonb) from (
    select jsonb_build_object('rang',lpad(row_number() over (order by coalesce(t.s,0) desc, c.photo is null, c.id)::text,3,'0'),'id',c.id,'nom',c.nom,'univers',c.univers,'descr',c.descr,'photo',c.photo,'tailles',loge_tailles(c.id,c.tailles),'score',coalesce(t.s,0)) x
    from loge_costumes c left join t on t.id=c.id where c.actif and not c.brouillon
    order by coalesce(t.s,0) desc, c.photo is null, c.id limit greatest(1,least(p_n,12))) q;
$$;
create or replace function public.loge_admin_univers(p_token text) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not loge_ok(p_token) then raise exception 'session'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'label',u.label,'bg',u.bg,'ordre',u.ordre,
    'nb',(select count(*) from loge_costumes c where c.univers=u.id and c.actif and not c.brouillon),
    'ex',(select coalesce(sum((t->>'n')::int),0) from loge_costumes c, jsonb_array_elements(c.tailles) t where c.univers=u.id and c.actif and not c.brouillon),
    'out',(select count(*) from loge_locations l join loge_costumes c on c.id=l.costume_id where c.univers=u.id and l.rendu is null)) order by u.ordre,u.label),'[]'::jsonb) from loge_univers u);
end $$;
create or replace function public.loge_admin_costumes(p_token text,p_univers text,p_q text) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not loge_ok(p_token) then raise exception 'session'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'ref',c.ref,'nom',c.nom,'univers',c.univers,'descr',c.descr,'photo',c.photo,'prix',c.prix,'tailles',loge_tailles(c.id,c.tailles)) order by c.nom),'[]'::jsonb)
    from (select * from loge_costumes c where c.actif and not c.brouillon and (p_univers is null or c.univers=p_univers)
      and (coalesce(p_q,'')='' or c.nom ilike '%'||p_q||'%' or c.ref ilike '%'||p_q||'%') order by c.nom limit 400) c);
end $$;
create or replace function public.loge_costumes_recherche(p_token text,p_q text) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not loge_ok(p_token) then raise exception 'session'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'nom',c.nom,'ref',c.ref,'univers',c.univers,'prix',c.prix,'tailles',loge_tailles(c.id,c.tailles))),'[]'::jsonb)
    from (select * from loge_costumes where actif and not brouillon and (nom ilike '%'||p_q||'%' or ref ilike '%'||p_q||'%') order by nom limit 12) c);
end $$;
create or replace function public.loge_costume_enregistrer(p_token text,p jsonb) returns bigint language plpgsql security definer set search_path=public as $$
declare i bigint;
begin
  if not loge_ok(p_token) then raise exception 'session'; end if;
  if (p->>'id') is null then
    insert into loge_costumes(ref,nom,univers,descr,photo,tailles,prix) values(nullif(trim(p->>'ref'),''),p->>'nom',p->>'univers',coalesce(p->>'descr',''),p->>'photo',coalesce(p->'tailles','[]'),(p->>'prix')::numeric) returning id into i;
  else
    i:=(p->>'id')::bigint;
    update loge_costumes set ref=nullif(trim(p->>'ref'),''),nom=p->>'nom',univers=p->>'univers',descr=coalesce(p->>'descr',''),photo=p->>'photo',tailles=coalesce(p->'tailles','[]'),prix=(p->>'prix')::numeric,brouillon=false,maj=now() where id=i;
  end if;
  return i;
end $$;
create or replace function public.loge_brouillons(p_token text) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not loge_ok(p_token) then raise exception 'session'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id',id,'nom','','univers',univers,'descr','','photo',photo,'tailles','[]'::jsonb) order by id desc),'[]'::jsonb) from loge_costumes where actif and brouillon);
end $$;
create or replace function public.loge_brouillons_creer(p_token text,p_photos jsonb) returns int language plpgsql security definer set search_path=public as $$
declare ph text; n int:=0; u text;
begin
  if not loge_ok(p_token) then raise exception 'session'; end if;
  select id into u from loge_univers order by ordre,label limit 1;
  for ph in select jsonb_array_elements_text(p_photos) loop
    insert into loge_costumes(nom,univers,photo,brouillon) values('À compléter',u,ph,true); n:=n+1;
  end loop;
  return n;
end $$;
