# ProyectoMySQL_MediCita_SandovalJoseMiguel
# MediCita IPS · Base de datos

**Autor:** Jose Miguel Sandoval
**Motor:** MySQL 8.4 · **Base:** `medicita_ips` · **Fecha de corte de los datos:** 2026-11-30

## 1. Descripción del proyecto

MediCita IPS es una institución prestadora de servicios de salud con cuatro sedes en el área metropolitana de Bucaramanga: Cabecera, Cañaveral, Girón Centro y Piedecuesta. Hoy la agenda, las atenciones y la facturación viven en hojas de cálculo y documentos de Word.

En octubre de 2026 pasaron tres problemas:

1. Dos pacientes quedaron agendados a la misma hora con el mismo médico.
2. A una paciente se le formuló un medicamento al que es alérgica.
3. La cartera con una aseguradora no cuadró por más de 3 millones.

Este proyecto construye la base de datos del nuevo sistema. Incluye el modelo, la estructura, datos de prueba, consultas, funciones, procedimientos, triggers, eventos y permisos por rol. Así esos tres problemas quedan controlados por la propia base de datos.

## 2. Cómo ejecutarlo

Ejecuta los scripts en este orden sobre un servidor MySQL 8 que no tenga la base `medicita_ips`. Desde la terminal, en la carpeta del proyecto:

```
mysql -u root -p < sql/01_ddl.sql
mysql -u root -p < sql/02_dml.sql
mysql -u root -p < sql/03_dql.sql
mysql -u root -p < sql/04_funciones.sql
mysql -u root -p < sql/05_procedimientos.sql
mysql -u root -p < sql/06_triggers.sql
mysql -u root -p < sql/07_eventos.sql
mysql -u root -p < sql/08_dcl.sql
```

> `01_ddl.sql` empieza con `DROP DATABASE IF EXISTS medicita_ips;`, así que se puede ejecutar las veces que sea necesario.
> Las sentencias que deben fallar a propósito están marcadas con `-- ⚠️ ESPERADO: ERROR <código>`. Para que el script siga después de esos errores, ejecútalo con `mysql -u root -p --force < archivo.sql`.

## 3. Reglas corroboradas

Comparé cada regla del análisis preliminar con lo que dijeron los tres entrevistados: Dra. Marcela Ortiz (directora médica), Hernán Rueda (agendamiento) y Liliana Prada (facturación).

| Regla | ¿Se confirma? | Evidencia (quién lo dijo) | Corrección |
| --- | --- | --- | --- |
| RP-01: Un paciente se identifica por tipo y número de documento; el número no se repite dentro del mismo tipo. | Sí | Hernán Rueda: "Un mismo número puede existir con dos tipos distintos, pero no se repite dentro del mismo tipo." | Ninguna. Se protege con `UNIQUE (document_type_id, document_number)`. |
| RP-02: Cada paciente tiene un único número de teléfono. | No | Hernán Rueda: "Los pacientes tienen varios teléfonos, y uno es el principal para llamarlos." | Un paciente tiene uno o varios teléfonos y exactamente uno es el principal. |
| RP-03: Cada médico pertenece a una sola especialidad. | No | Dra. Ortiz: "La doctora Salazar es internista y también cardióloga, y atiende citas de las dos." | Un médico puede tener una o varias especialidades (relación N:M). |
| RP-04: Un médico puede atender en varias sedes. | Sí | Dra. Ortiz: "Un mismo médico atiende en varias sedes, y eso no depende de la especialidad." | Se agrega que sedes y especialidades son hechos independientes (ver 4FN). |
| RP-05: La duración de una cita depende del tipo de cita. | Sí | Hernán Rueda: "Se escoge el tipo de cita… que define cuánto dura: 20, 30 o 40 minutos." | Ninguna. |
| RP-06: Un médico no puede tener dos citas que se crucen en el tiempo. | Sí, incompleta | Hernán Rueda: "Un médico no puede tener dos citas que se crucen, y un consultorio tampoco." | Tampoco un consultorio puede tener dos citas cruzadas. Las citas canceladas no cuentan para el cruce. |
| RP-07: No se puede agendar fuera del horario del médico ni durante sus novedades. | Sí | Dra. Ortiz: "Cada médico tiene un horario semanal… En esas fechas no se le puede agendar nada." | Ninguna. La novedad tiene fecha de inicio y de fin. |
| RP-08: Una cita se puede cancelar sin indicar el motivo. | No | Hernán Rueda: "Toda cancelación lleva un motivo de nuestra lista… Sin motivo no se cancela." | El motivo es obligatorio y debe existir en el catálogo de motivos. |
| RP-09: Cada cambio de estado de una cita queda en un historial. | Sí | Hernán Rueda: "Necesito saber cada cambio de estado: de cuál a cuál pasó, cuándo y quién lo hizo." | Se precisa qué se guarda: estado anterior, estado nuevo, fecha y responsable. |
| RP-10: Un paciente puede tener varias afiliaciones vigentes al mismo tiempo. | No | Hernán Rueda: "Guardamos el historial, pero solo puede haber una afiliación vigente. Si no tiene ninguna vigente, se atiende como particular." | Puede tener varias afiliaciones en el historial, pero solo una vigente. Sin afiliación vigente, se atiende como PARTICULAR. |
| RP-11: Una atención registra uno o varios diagnósticos, y uno de ellos es el principal. | Sí | Dra. Ortiz: "Uno o varios diagnósticos con el código CIE-10 y uno de ellos marcado como principal." | Se agrega que un mismo diagnóstico no se repite en la misma atención. |
| RP-12: No se formula un medicamento cuyo principio activo cause alergia al paciente. | Sí | Dra. Ortiz: "Las alergias del paciente se registran contra el principio activo… no contra la marca." | Ninguna. La alergia se guarda contra el principio activo. |
| RP-13: El precio de un servicio es el mismo para todos los pacientes. | No | Liliana Prada: "El precio no es el mismo para todos: depende del plan del paciente… las tarifas cambian." | El precio depende del servicio, del plan y de la fecha. Se usa la tarifa vigente el día de la atención. |
| RP-14: Si hay un error en una factura, se borra y se vuelve a hacer. | No | Liliana Prada: "Las facturas nunca se borran: si hay un error se anulan." | La factura nunca se borra; se anula con fecha y motivo. |
| RP-15: Una factura queda PAGADA cuando sus abonos completan el total. | Sí, incompleta | Liliana Prada: "PAGADA cuando los abonos completan el total." | Faltan los demás estados: PENDIENTE, PARCIAL (tiene abonos), VENCIDA (30 días sin pago completo) y ANULADA. |

### Reglas que faltaban

| Regla | Evidencia (quién lo dijo) |
| --- | --- |
| RP-16: La cita es en una especialidad que el médico tenga, en un consultorio de una sede donde el médico atienda y dentro de su horario. | Hernán Rueda |
| RP-17: La cita nace PROGRAMADA y pasa a CONFIRMADA, ATENDIDA, CANCELADA o NO_ASISTIO. | Hernán Rueda |
| RP-18: Los signos vitales fuera de rangos posibles se rechazan. | Dra. Ortiz |
| RP-19: Una fórmula tiene uno o varios medicamentos, cada uno con dosis, frecuencia y número de días. | Dra. Ortiz |
| RP-20: Cada examen tiene unidad y rango de referencia; se debe saber si el resultado quedó fuera del rango. | Dra. Ortiz |
| RP-21: El paciente tiene uno o más contactos de emergencia. | Hernán Rueda |
| RP-22: El día anterior a cada cita se envía un recordatorio (SMS, correo o WhatsApp) y se guarda si se envió o falló. | Hernán Rueda |
| RP-23: La encuesta de satisfacción va de 1 a 5, con comentario opcional, solo para citas atendidas y una sola vez por cita. | Hernán Rueda |
| RP-24: Cada atención genera una sola factura; cada renglón copia el precio del día y no cambia si la tarifa cambia después. | Liliana Prada |
| RP-25: Cada plan tiene un porcentaje de copago que paga el paciente; el resto se cobra a la aseguradora. El particular paga el 100 %. | Liliana Prada |
| RP-26: Una factura se puede pagar en varios abonos, con distintos medios de pago; cada abono es mayor que 0. | Liliana Prada |
| RP-27: Una factura sin pagar completa 30 días después de su emisión pasa a VENCIDA. | Liliana Prada |
| RP-28: A fin de mes el sistema arma solo un resumen de producción por médico (atenciones y valor facturado). | Liliana Prada |

## 4. Normalización

### 1FN · Atributos multivaluados

Hernán Rueda dijo que "los pacientes tienen varios teléfonos". Si guardáramos los teléfonos en una sola columna de `patients` (por ejemplo `'3001234567, 6076543210'`), la columna tendría varios valores y no se podría marcar cuál es el principal. Por eso los teléfonos van en su propia tabla `patient_phones`, con una fila por teléfono y una columna `is_primary`. Lo mismo pasa con los contactos de emergencia (`emergency_contacts`) y con los diagnósticos de una atención (`attention_diagnoses`).

### 2FN · Dependencia parcial de una clave compuesta

En la tabla de diagnósticos de una atención, la clave natural es `(attention_id, cie10_code_id)`, porque un diagnóstico no se repite en la misma atención. Si en esa tabla guardáramos también el nombre del diagnóstico (`'Hipertensión esencial'`), ese nombre dependería solo de `cie10_code_id` y no de la clave completa. Esa es una dependencia parcial. El nombre se movió a la tabla catálogo `cie10_codes`, y `attention_diagnoses` solo guarda la referencia y si es el diagnóstico principal.

### 3FN · Dependencia transitiva

Si la tabla `appointments` guardara el tipo de cita y también su duración en minutos, tendríamos `cita → tipo de cita → duración`. La duración no depende de la cita sino del tipo, como dijo Hernán Rueda: "el tipo de cita… define cuánto dura". Esa es una dependencia transitiva. Se eliminó creando `appointment_types` con su `duration_minutes`, y la cita solo guarda `appointment_type_id`.

### 4FN · Especialidades y sedes de un médico

La Dra. Ortiz explicó que el doctor Pabón es pediatra y dermatólogo y atiende en Cabecera y en Girón, y que "puede atender cualquiera de las dos especialidades en cualquiera de las dos sedes". Si usáramos una sola tabla `(médico, especialidad, sede)`, tendríamos que guardar todas las combinaciones:

| doctor | specialty | site |
| --- | --- | --- |
| Pabón | Pediatría | Cabecera |
| Pabón | Pediatría | Girón Centro |
| Pabón | Dermatología | Cabecera |
| Pabón | Dermatología | Girón Centro |

Hay dos dependencias multivaluadas independientes: médico →→ especialidad y médico →→ sede. Eso viola la 4FN y provoca anomalías. Si Pabón empieza a atender en Piedecuesta, hay que insertar dos filas, una por especialidad. Si se olvida una, la tabla diría que no puede atender dermatología allí, y eso es falso.

La solución fue descomponer en dos tablas independientes:

- `doctor_specialties (doctor_id, specialty_id)`
- `doctor_sites (doctor_id, site_id)`

Ahora agregar una sede es una sola fila, y la combinación válida se obtiene con un JOIN.

## 5. Diagramas

_(Pendiente: Paso 4 y Paso 5)_

- Diagrama entidad-relación hecho a mano: `diagramas/00_diagrama_er.jpg`
- Diagrama lógico por ingeniería inversa: `diagramas/00_diagrama_logico.png`

## 6. Reglas que no protege la estructura

_(Pendiente: se completa en la fase 5)_

## 7. Características de cada función

_(Pendiente: Paso 8)_

## 8. Roles y permisos

_(Pendiente: Paso 12)_

## 9. Evidencias

_(Pendiente: capturas de 3 consultas, 1 procedimiento, 1 trigger y 1 evento)_

## 10. Conclusiones

_(Pendiente)_
