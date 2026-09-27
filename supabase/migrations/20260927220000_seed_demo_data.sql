-- Datos de demostración para visualizar el panel con contenido realista.
-- Identificados con el prefijo "Demo ·" y diseñados para poder reejecutarse sin duplicados.
begin;
do $$
declare
  v_box uuid := '16ff8a04-1106-43ce-91ed-9b698c68e505';
  v_athlete uuid := 'b34eb83a-ca69-4874-b20b-b0fbc91332a5';
  v_coach uuid := '55b61b1f-ad77-4e02-ac80-d6c2e2d20c98';
  v_admin uuid := 'e6450675-2265-4fe7-93aa-2fa555e3ce0c';
  c1 uuid; c2 uuid; c3 uuid; e1 uuid; e2 uuid; p1 uuid; p2 uuid; x1 uuid; x2 uuid; b2 uuid;
begin
  delete from public.class_booking_cancellations where class_id in (select id from public.classes where title like 'Demo ·%');
  delete from public.class_bookings where class_id in (select id from public.classes where title like 'Demo ·%');
  delete from public.event_registrations where event_id in (select id from public.events where title like 'Demo ·%');
  delete from public.finance_audit_log where record_id in (select id from public.payments where concept like 'Demo ·%' union all select id from public.expenses where concept like 'Demo ·%');
  delete from public.verifactu_records where description like 'Demo ·%';
  delete from public.progress_entries where notes like 'Demo ·%';
  delete from public.payments where concept like 'Demo ·%';
  delete from public.expenses where concept like 'Demo ·%';
  delete from public.events where title like 'Demo ·%';
  delete from public.classes where title like 'Demo ·%';

  insert into public.box_hours(box_id,weekday,open_time,close_time,closed,notes)
  values (v_box,0,null,null,true,'Demo · Cerrado'),(v_box,1,'06:30','21:30',false,'Demo · Horario habitual'),
    (v_box,2,'06:30','21:30',false,'Demo · Horario habitual'),(v_box,3,'06:30','21:30',false,'Demo · Horario habitual'),
    (v_box,4,'06:30','21:30',false,'Demo · Horario habitual'),(v_box,5,'06:30','21:30',false,'Demo · Horario habitual'),
    (v_box,6,'09:00','14:00',false,'Demo · Horario habitual')
  on conflict (box_id,weekday) do update set open_time=excluded.open_time,close_time=excluded.close_time,closed=excluded.closed,notes=excluded.notes;

  insert into public.user_box_memberships(user_id,box_id) values (v_athlete,v_box),(v_coach,v_box),(v_admin,v_box) on conflict (user_id,box_id) do nothing;

  insert into public.payments(box_id,user_id,concept,amount_cents,currency,status,due_date,paid_at,provider,provider_reference,category,payment_method,notes)
  values (v_box,v_athlete,'Demo · Cuota septiembre',5900,'EUR','paid',current_date,current_date + time '10:00','demo','DEMO-SEP-001','Cuota mensual','Domiciliación','Demo · Pago confirmado') returning id into p1;
  insert into public.payments(box_id,user_id,concept,amount_cents,currency,status,due_date,paid_at,provider,provider_reference,category,payment_method,notes)
  values (v_box,v_athlete,'Demo · Matrícula',3000,'EUR','pending',current_date + 7,null,'demo','DEMO-MAT-001','Matrícula','Transferencia','Demo · Pendiente de pago') returning id into p2;

  insert into public.classes(box_id,title,description,starts_at,duration_minutes,capacity,coach_id,workout,equipment,location,created_by)
  values (v_box,'Demo · CrossTraining','Sesión general de fuerza y acondicionamiento.',date_trunc('day',now()) + interval '1 day 18 hours',60,14,v_coach,'EMOM 12 · 4 ejercicios','Kettlebell, remo, barra','Sala principal',v_admin) returning id into c1;
  insert into public.classes(box_id,title,description,starts_at,duration_minutes,capacity,coach_id,workout,equipment,location,created_by)
  values (v_box,'Demo · Weightlifting','Técnica y fuerza de levantamientos olímpicos.',date_trunc('day',now()) + interval '1 day 20 hours',75,10,v_coach,'5x3 Power Clean','Barras, discos','Zona de halterofilia',v_admin) returning id into c2;
  insert into public.classes(box_id,title,description,starts_at,duration_minutes,capacity,coach_id,workout,equipment,location,created_by)
  values (v_box,'Demo · Open Gym','Entrenamiento libre con supervisión del coach.',date_trunc('day',now()) + interval '2 days 10 hours',90,20,v_coach,'Open Gym','Material completo','Sala principal',v_admin) returning id into c3;

  insert into public.class_bookings(class_id,user_id,status) values (c1,v_athlete,'booked');
  insert into public.class_bookings(class_id,user_id,status) values (c2,v_athlete,'booked') returning id into b2;
  update public.class_bookings set status='cancelled' where id=b2;

  insert into public.events(box_id,title,description,starts_at,ends_at,location,capacity,price_cents,currency,created_by)
  values (v_box,'Demo · Seminario de movilidad','Seminario práctico de movilidad y prevención.',date_trunc('day',now()) + interval '6 days 10 hours',date_trunc('day',now()) + interval '6 days 12 hours','Sala principal',20,1500,'EUR',v_admin) returning id into e1;
  insert into public.events(box_id,title,description,starts_at,ends_at,location,capacity,price_cents,currency,created_by)
  values (v_box,'Demo · Throwdown WodIO','Competición interna por equipos.',date_trunc('day',now()) + interval '13 days 9 hours',date_trunc('day',now()) + interval '13 days 14 hours','Box WodIO',30,2500,'EUR',v_admin) returning id into e2;
  insert into public.event_registrations(event_id,user_id,status) values (e1,v_athlete,'registered');

  insert into public.expenses(box_id,concept,amount_cents,currency,expense_date,category,supplier,notes,created_by)
  values (v_box,'Demo · Material deportivo',42500,'EUR',current_date - 4,'Material','Rogue Europe','Demo · Compra de material',v_admin) returning id into x1;
  insert into public.expenses(box_id,concept,amount_cents,currency,expense_date,category,supplier,notes,created_by)
  values (v_box,'Demo · Limpieza mensual',18500,'EUR',current_date - 2,'Servicios','Limpiezas Navarra','Demo · Servicio mensual',v_admin) returning id into x2;

  insert into public.finance_audit_log(box_id,record_type,record_id,action,changed_by,changed_at,reason,old_data,new_data)
  values (v_box,'payment',p1,'update',v_admin,now(),'Demo · Corrección de referencia',jsonb_build_object('provider_reference','DEMO-SEP-OLD'),jsonb_build_object('provider_reference','DEMO-SEP-001'));

  insert into public.progress_entries(box_id,user_id,exercise,value,unit,reps,recorded_at,notes)
  values (v_box,v_athlete,'Back Squat',100,'kg',5,current_date - 30,'Demo · PR de referencia'),
         (v_box,v_athlete,'Deadlift',140,'kg',3,current_date - 18,'Demo · Progreso'),
         (v_box,v_athlete,'Clean',80,'kg',2,current_date - 7,'Demo · Progreso');

  insert into public.verifactu_config(box_id,enabled,mode,issuer_name,issuer_nif,issuer_address,software_name,software_id,software_version,installation_number,next_invoice_number,invoice_series,aeat_environment)
  values (v_box,true,'verifactu','WodIO Demo Box','B00000000','Calle Demo 1, Pamplona','WodIO','WODIO','1.0.0','DEMO-01',104,'F','test')
  on conflict (box_id) do update set enabled=excluded.enabled,mode=excluded.mode,issuer_name=excluded.issuer_name,issuer_nif=excluded.issuer_nif,issuer_address=excluded.issuer_address,software_name=excluded.software_name,software_id=excluded.software_id,software_version=excluded.software_version,installation_number=excluded.installation_number,next_invoice_number=excluded.next_invoice_number,invoice_series=excluded.invoice_series,aeat_environment=excluded.aeat_environment;

  insert into public.verifactu_records(box_id,record_type,invoice_series,invoice_number,invoice_date,issuer_nif,recipient_nif,recipient_name,description,taxable_base_cents,vat_rate,vat_amount_cents,total_amount_cents,currency,operation_date,hash_algorithm,record_hash,qr_url,aeat_status,payload)
  values (v_box,'alta','F','103',current_date,'B00000000','X00000000','Cliente Demo','Demo · Cuota mensual',5900,21,1239,7139,'EUR',current_date,'SHA-256',repeat('a',64),'https://example.com/demo-qr','accepted',jsonb_build_object('demo',true,'source','WodIO demo'));
end $$;
commit;
