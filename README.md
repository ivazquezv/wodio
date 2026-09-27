# WodIO

> Plataforma de gestión para boxes de CrossTraining, gimnasios y entrenamiento funcional.

WodIO centraliza la gestión del box y la experiencia del atleta en una única plataforma: clases, horarios, reservas, atletas, coaches, asistencia, programación, eventos, pagos, contabilidad, facturación y seguimiento del progreso.

## Qué es WodIO

WodIO está pensado para conectar las tres partes principales de un box:

- **Gestor / propietario:** control operativo, usuarios, coaches, horarios, reservas, eventos, finanzas y configuración.
- **Coach:** clases, programación, disponibilidad y control de asistencia.
- **Atleta:** calendario, reservas, entrenamientos, evolución, pagos y facturas.

El objetivo es reducir tareas administrativas, centralizar la información y facilitar una experiencia digital coherente para toda la comunidad del box.

## Funcionalidades

### Gestión del box
- Gestión de usuarios y roles.
- Gestión de coaches.
- Gestión de múltiples boxes y pertenencia de usuarios.
- Configuración de datos y logo del box.
- Horario habitual y programación mensual.
- Gestión de clases, plazas y coaches.
- Eventos y registros de participantes.
- Control de asistencia.
- Configuración de políticas de reservas y cancelaciones.

### Experiencia del atleta
- Dashboard personal.
- Calendario semanal del box.
- Reserva y cancelación de clases.
- Visualización de asistentes a las clases.
- Registro y seguimiento de resultados.
- Métricas y evolución del rendimiento.
- Perfil y fotografía del atleta.
- Gestión de pagos.
- Consulta y descarga de facturas.

### Finanzas
- Ingresos del box.
- Gastos y proveedores.
- Pagos realizados por atletas.
- Estados de pago.
- Métodos de pago configurables por box.
- Soporte para Stripe, PayPal, Bizum, transferencia, domiciliación y efectivo como métodos configurables.
- Exportación de ingresos y gastos a Excel y PDF.
- Auditoría de modificaciones financieras.

> La configuración de Stripe y PayPal está preparada en la aplicación para definir métodos y enlaces de pago. La integración completa de APIs, checkout y webhooks de confirmación requiere la configuración de las credenciales de cada proveedor.

### Facturación y VERI*FACTU
WodIO incluye la estructura necesaria para preparar la gestión de facturas y registros relacionados con VERI*FACTU:

- Configuración fiscal por box.
- Series y numeración de facturas.
- Datos fiscales del emisor.
- Datos del cliente.
- Base imponible, IVA y total.
- Registro encadenado mediante hash.
- Estados del registro.
- Preparación de información para una futura integración con AEAT.
- Generación y descarga de facturas en PDF.

La implementación actual debe considerarse una **preparación técnica del sistema**, no una certificación de cumplimiento fiscal. La integración efectiva con AEAT y los requisitos definitivos de VERI*FACTU deben completarse y validarse según la normativa aplicable.

### Coaches y control horario
- Disponibilidad habitual de coaches.
- Turnos.
- Registro de entrada y salida.
- Seguimiento del tiempo trabajado.
- Asociación de coaches con clases.

## Arquitectura

**Frontend**
- HTML5
- CSS3
- JavaScript
- Phosphor Icons
- Diseño responsive para escritorio, tablet y móvil.

**Backend y datos**
- Supabase.
- PostgreSQL.
- Supabase Auth.
- Row Level Security (RLS).
- Supabase Storage para logos y fotografías.
- Funciones SQL con privilegios controlados para operaciones sensibles.

**Infraestructura**
- GitHub para control de versiones.
- Netlify para despliegue de la aplicación web.
- Assets estáticos y vídeos servidos desde `public`.

## Estructura del proyecto

~~~text
wodio/
├── public/
│   ├── index.html
│   ├── login.html
│   ├── dashboard.html
│   ├── classes.html
│   ├── payments.html
│   ├── box-admin.html
│   ├── create-box.html
│   ├── register.html
│   ├── css/
│   ├── js/
│   └── assets/
├── supabase/
│   └── migrations/
└── README.md
~~~

Las migraciones de `supabase/migrations/` contienen la evolución del modelo de datos, políticas RLS, funciones y configuración de la plataforma.

## Seguridad
- Separación de usuarios por box.
- Roles de atleta, coach y administrador.
- Control de pertenencia a boxes.
- Políticas RLS en las tablas principales.
- Funciones privadas para operaciones sensibles.
- Auditoría de modificaciones financieras.
- Restricciones sobre registros financieros y facturación.
- Almacenamiento separado de fotografías y logos.

Las credenciales privadas de proveedores de pago no deben almacenarse en tablas públicas ni en el frontend.

## Reservas
- Antelación máxima para reservar.
- Tiempo límite para cancelar.
- Límite semanal de cancelaciones.
- Control del pago del mes en curso.
- Registro de cancelaciones.
- Control de reservas asociadas al box activo.

Estas reglas se validan también en base de datos para evitar depender exclusivamente de la interfaz.

## Datos de demostración
- Usuarios existentes.
- Horarios.
- Clases.
- Eventos.
- Pagos.
- Gastos.
- Progreso de atletas.
- Reservas.
- Cancelaciones.
- Inscripciones a eventos.
- Auditoría financiera.
- Configuración y registros de VERI*FACTU.

Los datos de demo están identificados con el prefijo `Demo ·`.

## Puesta en marcha

### Requisitos
- Un proyecto Supabase.
- Un navegador moderno.
- Acceso al repositorio.
- Para el despliegue web, una cuenta de Netlify o un servicio equivalente.

### Frontend
~~~bash
git clone https://github.com/ivazquezv/wodio.git
cd wodio
~~~

La aplicación web estática puede ejecutarse sirviendo la carpeta `public` con cualquier servidor web estático.

### Base de datos
Las migraciones de Supabase se encuentran en `supabase/migrations/` y deben aplicarse sobre el proyecto Supabase destinado a WodIO.

No se deben copiar credenciales privadas de Supabase, proveedores de pago o servicios externos al código público.

## SEO y presencia pública
- Title y meta description orientados a búsquedas relevantes.
- Open Graph para compartir en redes sociales.
- Metadatos para X/Twitter.
- Datos estructurados `SoftwareApplication`.
- Contenido diferenciado para gestores, atletas y comunidad.
- Diseño responsive.

La siguiente fase puede incorporar `robots.txt`, `sitemap.xml`, URL canónica, imagen social 1200×630, páginas SEO específicas e integración con Google Search Console y analítica.

## Evolución móvil

WodIO está construido con una interfaz responsive, por lo que la evolución a móvil es viable.

1. **PWA:** aplicación instalable desde navegador con experiencia móvil optimizada.
2. **iOS y Android:** si el producto lo requiere, crear aplicaciones móviles reutilizando backend, autenticación y datos actuales.
3. **Notificaciones push:** reservas, cambios de horario, eventos, pagos y comunicaciones del box.

El objetivo es mantener una única plataforma de datos mientras se amplían los canales de acceso.

## Estado actual

WodIO se encuentra en desarrollo activo. Actualmente están implementados los principales bloques de gestión:

- Autenticación.
- Gestión de boxes.
- Usuarios y roles.
- Coaches.
- Clases y horarios.
- Reservas.
- Asistencia.
- Eventos.
- Pagos.
- Finanzas.
- Facturación.
- Preparación de VERI*FACTU.
- Seguimiento del progreso.
- Logos y fotografías.
- Métodos de pago.
- Configuración multi-box.

Algunas integraciones externas, especialmente las pasarelas de pago y la comunicación efectiva con servicios fiscales externos, requieren configuración y desarrollo adicional antes de considerarse producción.

## Contribución

Las contribuciones y mejoras pueden realizarse mediante pull requests.

Antes de modificar funcionalidades sensibles se recomienda revisar RLS, políticas de Supabase, funciones SQL, migraciones, permisos por box e impacto sobre atletas, coaches y administradores.

Los cambios de base de datos deben realizarse mediante nuevas migraciones, evitando modificar manualmente el histórico existente.

## Autor

WodIO ha sido creado y desarrollado por Iván Vázquez Vidador como proyecto orientado a la digitalización y optimización de la gestión de boxes y centros de entrenamiento funcional.

## Contacto
- **WodIO:** contacto@wodio.app
- **Desarrollo:** contacta@ivanvazquezv.com
- **Web:** https://wodio.netlify.app

## Licencia

Este proyecto se distribuye bajo licencia MIT.