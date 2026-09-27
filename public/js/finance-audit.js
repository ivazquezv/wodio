document.addEventListener("DOMContentLoaded",async()=>{
  const ctx=await WodIOApp.requireUser({roles:["box_admin","super_admin"]});
  if(!ctx)return;
  const boxId=ctx.profile?.box_id;
  if(!boxId)return;
  const $=id=>document.getElementById(id);
  const name=u=>[u?.first_name,u?.last_name].filter(Boolean).join(" ")||"Usuario";
  const esc=v=>WodIOApp.escapeHtml(v??"");
  let users=[], payments=[], expenses=[], audits=[];

  const style=document.createElement("style");
  style.textContent=".finance-audit-actions{white-space:nowrap}.finance-audit-modal textarea{resize:vertical}";
  document.head.appendChild(style);

  function ensureUI(){
    const table=$("financeTable");
    if(!table)return false;
    if(!$("financeAuditTable")){
      const card=document.createElement("section");
      card.className="app-card finance-audit-card";
      card.style.marginTop="18px";
      card.innerHTML='<div class="app-card-head"><div><h3>Historial de cambios</h3><p>Quién modificó cada movimiento, qué campos cambiaron, el motivo y la fecha y hora.</p></div></div><div id="financeAuditTable" class="app-table-wrap"></div>';
      table.closest(".app-card")?.after(card);
    }
    if(!$("financeAuditModal")){
      const modal=document.createElement("div");
      modal.className="admin-modal finance-audit-modal";
      modal.id="financeAuditModal";
      modal.hidden=true;
      modal.innerHTML='<section class="admin-modal-card"><div class="admin-modal-head"><h3 id="financeAuditTitle">Editar movimiento</h3><button class="app-btn" type="button" id="financeAuditClose">Cerrar</button></div><div id="financeAuditMessage" class="app-message" aria-live="polite"></div><form id="financeAuditForm" class="app-form"><input type="hidden" id="financeAuditId"><input type="hidden" id="financeAuditType"><div id="financeAuditFields"></div><div class="app-actions"><button class="app-btn primary" type="submit">Guardar cambios</button><button class="app-btn" type="button" id="financeAuditCancel">Cancelar</button></div></form></section>';
      document.body.appendChild(modal);
      const close=()=>{modal.hidden=true;};
      $("financeAuditClose").onclick=close;$("financeAuditCancel").onclick=close;
      modal.onclick=e=>{if(e.target===modal)close();};
      $("financeAuditForm").onsubmit=save;
    }
    return true;
  }

  function render(){
    if(!ensureUI())return;
    const table=$("financeTable");
    const rows=[...payments.map(v=>({type:"payment",label:"Ingreso",date:v.paid_at||v.due_date||v.created_at,party:name(users.find(u=>u.id===v.user_id)),concept:v.concept,amount:v.amount_cents,status:v.status,id:v.id})),...expenses.map(v=>({type:"expense",label:"Gasto",date:v.expense_date,party:v.supplier||"Sin proveedor",concept:v.concept,amount:-v.amount_cents,status:"paid",id:v.id}))].sort((a,b)=>new Date(b.date)-new Date(a.date));
    table.innerHTML=rows.length?'<table class="app-table"><thead><tr><th>Fecha</th><th>Tipo</th><th>Cliente / proveedor</th><th>Concepto</th><th>Importe</th><th>Estado</th><th></th></tr></thead><tbody>'+rows.slice(0,40).map(v=>'<tr><td>'+WodIOApp.formatDate(v.date,{withYear:true})+'</td><td>'+v.label+'</td><td>'+esc(v.party)+'</td><td>'+esc(v.concept)+'</td><td>'+WodIOApp.euro(v.amount)+'</td><td><span class="app-badge '+(v.status==="paid"?"success":v.status==="pending"?"warning":"")+'">'+({paid:"Pagado",pending:"Pendiente",failed:"Fallido",cancelled:"Cancelado",refunded:"Devuelto"}[v.status]||v.status||"—")+'</span></td><td class="finance-audit-actions"><button class="app-btn" data-finance-edit="'+v.type+'|'+v.id+'">Editar</button></td></tr>').join("")+'</tbody></table>':'<div class="app-empty">No hay movimientos.</div>';
    const auditRows=audits.map(v=>{const before=v.old_data||{},after=v.new_data||{};const fields=Object.keys(after).filter(k=>JSON.stringify(before[k])!==JSON.stringify(after[k]));const changes=fields.map(k=>k+": "+String(before[k]??"—")+" → "+String(after[k]??"—")).join(" | ");return '<tr><td>'+WodIOApp.formatDateTime(v.changed_at)+'</td><td>'+esc(v.record_type==="payment"?"Ingreso":"Gasto")+'</td><td>'+esc(name(users.find(u=>u.id===v.changed_by)))+'</td><td>'+esc(v.reason)+'</td><td>'+esc(changes||"Sin cambios")+'</td></tr>';}).join("");
    $("financeAuditTable").innerHTML=auditRows?'<table class="app-table"><thead><tr><th>Fecha y hora</th><th>Movimiento</th><th>Administrador</th><th>Motivo</th><th>Campos modificados</th></tr></thead><tbody>'+auditRows+'</tbody></table>':'<div class="app-empty">Todavía no hay cambios registrados.</div>';
  }

  async function reload(){
    const [u,p,e,a]=await Promise.all([
      supabaseClient.from("profiles").select("id,first_name,last_name,role").eq("box_id",boxId),
      supabaseClient.from("payments").select("id,user_id,concept,amount_cents,status,due_date,paid_at,category,payment_method,provider_reference,notes,created_at,updated_at").eq("box_id",boxId).order("created_at",{ascending:false}),
      supabaseClient.from("expenses").select("id,concept,amount_cents,expense_date,category,supplier,notes,created_by,created_at,updated_at").eq("box_id",boxId).order("expense_date",{ascending:false}),
      supabaseClient.from("finance_audit_log").select("id,record_type,record_id,changed_by,changed_at,reason,old_data,new_data").eq("box_id",boxId).order("changed_at",{ascending:false}).limit(100)
    ]);
    if(u.error||p.error||e.error||a.error)return;
    users=u.data||[];payments=p.data||[];expenses=e.data||[];audits=a.data||[];render();
  }

  function openEdit(type,id){
    const v=type==="payment"?payments.find(x=>x.id===id):expenses.find(x=>x.id===id);if(!v)return;
    const modal=$("financeAuditModal"),fields=$("financeAuditFields");
    $("financeAuditId").value=id;$("financeAuditType").value=type;
    $("financeAuditTitle").textContent=type==="payment"?"Editar ingreso":"Editar gasto";
    if(type==="payment"){
      fields.innerHTML='<div class="app-form-grid"><div class="app-field"><label>Cliente</label><select id="faUser">'+users.filter(x=>x.role==="athlete").map(x=>'<option value="'+x.id+'">'+esc(name(x))+'</option>').join("")+'</select></div><div class="app-field"><label>Concepto</label><input id="faConcept" required></div><div class="app-field"><label>Importe (€)</label><input id="faAmount" type="number" min="0" step=".01" required></div><div class="app-field"><label>Fecha de ingreso</label><input id="faDate" type="date"></div><div class="app-field"><label>Vencimiento</label><input id="faDue" type="date"></div><div class="app-field"><label>Estado</label><select id="faStatus"><option value="paid">Pagado</option><option value="pending">Pendiente</option><option value="failed">Fallido</option><option value="cancelled">Cancelado</option><option value="refunded">Devuelto</option></select></div><div class="app-field"><label>Categoría</label><input id="faCategory"></div><div class="app-field"><label>Método de pago</label><input id="faMethod"></div><div class="app-field full"><label>Referencia</label><input id="faReference"></div><div class="app-field full"><label>Notas</label><input id="faNotes"></div><div class="app-field full"><label>Motivo del cambio <strong>(obligatorio)</strong></label><textarea id="faReason" rows="3" required placeholder="Ej.: Corrección según factura recibida"></textarea></div></div>';
      $("faUser").value=v.user_id||"";$("faConcept").value=v.concept||"";$("faAmount").value=(v.amount_cents/100).toFixed(2);$("faDate").value=v.paid_at?new Date(v.paid_at).toISOString().slice(0,10):"";$("faDue").value=v.due_date||"";$("faStatus").value=v.status||"pending";$("faCategory").value=v.category||"";$("faMethod").value=v.payment_method||"";$("faReference").value=v.provider_reference||"";$("faNotes").value=v.notes||"";
    }else{
      fields.innerHTML='<div class="app-form-grid"><div class="app-field"><label>Concepto</label><input id="faConcept" required></div><div class="app-field"><label>Importe (€)</label><input id="faAmount" type="number" min="0" step=".01" required></div><div class="app-field"><label>Fecha</label><input id="faDate" type="date"></div><div class="app-field"><label>Categoría</label><input id="faCategory"></div><div class="app-field full"><label>Proveedor</label><input id="faSupplier"></div><div class="app-field full"><label>Notas</label><input id="faNotes"></div><div class="app-field full"><label>Motivo del cambio <strong>(obligatorio)</strong></label><textarea id="faReason" rows="3" required placeholder="Ej.: Corrección de factura del proveedor"></textarea></div></div>';
      $("faConcept").value=v.concept||"";$("faAmount").value=(v.amount_cents/100).toFixed(2);$("faDate").value=v.expense_date||"";$("faCategory").value=v.category||"";$("faSupplier").value=v.supplier||"";$("faNotes").value=v.notes||"";
    }
    modal.hidden=false;
  }

  async function save(ev){
    ev.preventDefault();
    const type=$("financeAuditType").value,id=$("financeAuditId").value,reason=$("faReason").value.trim(),msg=$("financeAuditMessage");
    if(!reason){WodIOApp.message(msg,"El motivo del cambio es obligatorio.");return;}
    let data;
    if(type==="payment")data={user_id:$("faUser").value,concept:$("faConcept").value.trim(),amount_cents:Math.round(+$("faAmount").value*100),due_date:$("faDue").value||null,status:$("faStatus").value,paid_at:$("faStatus").value==="paid"?($("faDate").value?new Date($("faDate").value+"T12:00:00").toISOString():new Date().toISOString()):null,category:$("faCategory").value.trim()||null,payment_method:$("faMethod").value.trim()||null,provider_reference:$("faReference").value.trim()||null,notes:$("faNotes").value.trim()||null};
    else data={concept:$("faConcept").value.trim(),amount_cents:Math.round(+$("faAmount").value*100),expense_date:$("faDate").value||new Date().toISOString().slice(0,10),category:$("faCategory").value.trim()||null,supplier:$("faSupplier").value.trim()||null,notes:$("faNotes").value.trim()||null};
    const fn=type==="payment"?"update_payment_with_audit":"update_expense_with_audit";
    const r=await supabaseClient.rpc(fn,{p_id:id,p_reason:reason,p_data:data});
    if(r.error){WodIOApp.message(msg,r.error.message);return;}
    WodIOApp.message(msg,"Cambios guardados y registrados.","success");
    setTimeout(async()=>{$("financeAuditModal").hidden=true;await reload();},500);
  }

  document.addEventListener("click",e=>{const b=e.target.closest("[data-finance-edit]");if(!b)return;const [type,id]=b.dataset.financeEdit.split("|");openEdit(type,id);});
  const table=$("financeTable");
  if(table){
    const observer=new MutationObserver(()=>{if(table.querySelector("table")&&!table.querySelector("[data-finance-edit]"))render();});
    observer.observe(table,{childList:true,subtree:true});
  }
  await reload();
});