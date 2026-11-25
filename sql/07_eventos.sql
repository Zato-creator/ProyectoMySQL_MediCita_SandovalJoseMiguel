-- 07_eventos.sql - MediCita IPS - Jose Miguel Sandoval
-- =====================================================================
-- MediCita IPS · 07_eventos.sql
-- 5 eventos (de menor a mayor dificultad) con sus pruebas.
-- Para probarlos sin esperar a medianoche, cada evento EMPIEZA en 2 segundos
-- (EVERY … STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND) y se espera con
-- SELECT SLEEP(4). Dentro del evento se usa la FECHA DE CORTE 2026-11-30,
-- no CURDATE(). Al final se apagan todos los eventos de prueba.
-- Orden de dificultad: E-3 y E-4 (un UPDATE), E-2 (INSERT … SELECT con
-- NOT EXISTS), E-1 (UPDATE que dispara T-3) y E-5 (resumen mensual).
-- =====================================================================

USE medicita_ips;

-- El "reloj" de los eventos debe estar encendido
SET GLOBAL event_scheduler = ON;
SHOW VARIABLES LIKE 'event_scheduler';

-- ---------------------------------------------------------------------
-- E-1 · evt_marcar_inasistencias_diario
-- Las citas PROGRAMADA o CONFIRMADA que empezaron antes del corte pasan a
-- NO_ASISTIO. El historial lo deja el trigger T-3 (responsable = usuario
-- SISTEMA, fecha = el corte a las 00:05).
-- ---------------------------------------------------------------------
SELECT id, start_at, status
FROM appointments
WHERE status IN ('PROGRAMADA', 'CONFIRMADA') AND start_at < '2026-11-30'
ORDER BY id;
-- Antes: 3 citas sin cerrar (167, 169 y 170)

DROP EVENT IF EXISTS evt_marcar_inasistencias_diario;

DELIMITER $$

CREATE EVENT evt_marcar_inasistencias_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
DO
BEGIN
    DECLARE v_sistema BIGINT;

    SELECT id INTO v_sistema FROM system_users WHERE role = 'SISTEMA' ORDER BY id LIMIT 1;

    SET @fecha_cambio_estado = '2026-11-30 00:05:00';     -- fecha del negocio para T-3

    UPDATE appointments
    SET status = 'NO_ASISTIO',
        updated_by = v_sistema
    WHERE status IN ('PROGRAMADA', 'CONFIRMADA')
      AND start_at < '2026-11-30';

    SET @fecha_cambio_estado = NULL;
END $$

DELIMITER ;

SELECT SLEEP(4) AS esperando;

SELECT a.id, a.start_at, a.status, h.previous_status, h.new_status, h.changed_at, u.username AS responsable
FROM appointments AS a
JOIN appointment_status_history AS h ON h.appointment_id = a.id AND h.new_status = 'NO_ASISTIO'
JOIN system_users AS u ON u.id = h.changed_by
WHERE a.id IN (167, 169, 170)
ORDER BY a.id;
-- Resultado esperado: las 3 en NO_ASISTIO, cada una con su fila en el historial
-- (… → NO_ASISTIO, 2026-11-30 00:05:00, sistema)

-- ---------------------------------------------------------------------
-- E-2 · evt_generar_recordatorios_diario
-- Crea un recordatorio PENDIENTE para cada cita del día siguiente al corte
-- (1-dic) que todavía no tenga uno. Canal: correo si el paciente tiene, si no SMS.
-- ---------------------------------------------------------------------
SELECT a.id, a.start_at, a.status, COUNT(r.id) AS recordatorios
FROM appointments AS a
LEFT JOIN reminders AS r ON r.appointment_id = a.id
WHERE DATE(a.start_at) = DATE_ADD('2026-11-30', INTERVAL 1 DAY)
  AND a.status IN ('PROGRAMADA', 'CONFIRMADA')
GROUP BY a.id, a.start_at, a.status
ORDER BY a.start_at;
-- Antes: varias citas del 1-dic con 0 recordatorios

DROP EVENT IF EXISTS evt_generar_recordatorios_diario;

DELIMITER $$

CREATE EVENT evt_generar_recordatorios_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
DO
BEGIN
    INSERT INTO reminders (appointment_id, channel, scheduled_for, status)
    SELECT a.id,
           IF(p.email IS NULL, 'SMS', 'CORREO'),
           '2026-11-30 08:00:00',
           'PENDIENTE'
    FROM appointments AS a
    JOIN patients AS p ON p.id = a.patient_id
    WHERE DATE(a.start_at) = DATE_ADD('2026-11-30', INTERVAL 1 DAY)
      AND a.status IN ('PROGRAMADA', 'CONFIRMADA')
      AND NOT EXISTS (SELECT 1 FROM reminders AS r WHERE r.appointment_id = a.id);
END $$

DELIMITER ;

SELECT SLEEP(4) AS esperando;

SELECT a.id, a.start_at, r.channel, r.scheduled_for, r.status
FROM appointments AS a
JOIN reminders AS r ON r.appointment_id = a.id
WHERE DATE(a.start_at) = '2026-12-01'
ORDER BY a.start_at, a.id;
-- Resultado esperado: TODAS las citas activas del 1-dic tienen ahora un recordatorio;
-- las nuevas quedan PENDIENTE para el 2026-11-30 08:00. Si el evento vuelve a
-- correr, no duplica nada (NOT EXISTS).

-- ---------------------------------------------------------------------
-- E-3 · evt_vencer_afiliaciones_diario
-- Inactiva las afiliaciones ACTIVA cuya fecha de fin ya pasó al corte.
-- ---------------------------------------------------------------------
SELECT id, patient_id, end_date, status
FROM affiliations
WHERE status = 'ACTIVA' AND end_date < '2026-11-30';
-- Antes: la afiliación 25 del paciente 23 (venció el 2026-11-15) sigue ACTIVA

DROP EVENT IF EXISTS evt_vencer_afiliaciones_diario;

CREATE EVENT evt_vencer_afiliaciones_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
DO
    UPDATE affiliations
    SET status = 'INACTIVA'
    WHERE status = 'ACTIVA'
      AND end_date < '2026-11-30';

SELECT SLEEP(4) AS esperando;

SELECT id, patient_id, end_date, status FROM affiliations WHERE patient_id = 23;
-- Resultado esperado: 25 | 23 | 2026-11-15 | INACTIVA

-- ---------------------------------------------------------------------
-- E-4 · evt_marcar_facturas_vencidas_diario
-- Las facturas PENDIENTE o PARCIAL emitidas hace más de 30 días al corte
-- pasan a VENCIDA.
-- ---------------------------------------------------------------------
SELECT status, COUNT(*) AS facturas
FROM invoices
WHERE status IN ('PENDIENTE', 'PARCIAL')
  AND DATEDIFF('2026-11-30', issued_at) > 30
GROUP BY status;
-- Antes: hay facturas PENDIENTE y PARCIAL emitidas antes del 31-oct

DROP EVENT IF EXISTS evt_marcar_facturas_vencidas_diario;

CREATE EVENT evt_marcar_facturas_vencidas_diario
ON SCHEDULE EVERY 1 DAY STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
DO
    UPDATE invoices
    SET status = 'VENCIDA'
    WHERE status IN ('PENDIENTE', 'PARCIAL')
      AND DATEDIFF('2026-11-30', issued_at) > 30;

SELECT SLEEP(4) AS esperando;

SELECT status, COUNT(*) AS facturas, MIN(issued_at) AS desde, MAX(issued_at) AS hasta
FROM invoices
GROUP BY status
ORDER BY status;
-- Resultado esperado: ya no hay PENDIENTE ni PARCIAL emitidas antes del 31-oct;
-- todas quedaron VENCIDA. Las de noviembre siguen PENDIENTE o PARCIAL.

-- ---------------------------------------------------------------------
-- E-5 · evt_resumen_produccion_mensual
-- El primer día de cada mes guarda en monthly_production_summary, por
-- médico, las atenciones y el valor facturado (sin anuladas) del mes
-- anterior. Con el corte 2026-11-30, "el primer día del mes siguiente" es el
-- 1-dic, así que genera el resumen de NOVIEMBRE de 2026.
-- ON DUPLICATE KEY UPDATE: si corre dos veces, actualiza en vez de fallar
-- (UNIQUE doctor_id, period_year, period_month).
-- ---------------------------------------------------------------------
DROP EVENT IF EXISTS evt_resumen_produccion_mensual;

DELIMITER $$

CREATE EVENT evt_resumen_produccion_mensual
ON SCHEDULE EVERY 1 MONTH STARTS CURRENT_TIMESTAMP + INTERVAL 2 SECOND
DO
BEGIN
    DECLARE v_corrida DATE;
    DECLARE v_desde DATE;
    DECLARE v_hasta DATE;

    SET v_corrida = DATE_ADD('2026-11-30', INTERVAL 1 DAY);                       -- 2026-12-01
    SET v_desde = DATE_SUB(v_corrida, INTERVAL 1 MONTH);                          -- 2026-11-01
    SET v_hasta = DATE_SUB(v_corrida, INTERVAL 1 DAY);                            -- 2026-11-30

    INSERT INTO monthly_production_summary (doctor_id, period_year, period_month,
                                            attentions_count, billed_amount, generated_at)
    SELECT d.id, YEAR(v_desde), MONTH(v_desde),
           COUNT(at.id),
           IFNULL(SUM(CASE WHEN i.status <> 'ANULADA' THEN i.total_amount ELSE 0 END), 0),
           NOW()
    FROM doctors AS d
    LEFT JOIN appointments AS ap ON ap.doctor_id = d.id
    LEFT JOIN attentions AS at ON at.appointment_id = ap.id
                              AND DATE(at.started_at) BETWEEN v_desde AND v_hasta
    LEFT JOIN invoices AS i ON i.attention_id = at.id
    GROUP BY d.id
    ON DUPLICATE KEY UPDATE attentions_count = VALUES(attentions_count),
                            billed_amount = VALUES(billed_amount),
                            generated_at = VALUES(generated_at);
END $$

DELIMITER ;

SELECT SLEEP(4) AS esperando;

SELECT s.period_year, s.period_month, CONCAT(d.first_name, ' ', d.last_name) AS medico,
       s.attentions_count, s.billed_amount
FROM monthly_production_summary AS s
JOIN doctors AS d ON d.id = s.doctor_id
WHERE s.period_year = 2026 AND s.period_month = 11
ORDER BY s.billed_amount DESC, medico;
-- Resultado esperado: 12 filas de noviembre de 2026 (una por médico), con los
-- mismos valores que CALL sp_reporte_produccion('2026-11-01', '2026-11-30')

-- ---------------------------------------------------------------------
-- Estado de los eventos y limpieza: no se dejan eventos de prueba activos
-- ---------------------------------------------------------------------
SELECT event_name, status, last_executed IS NOT NULL AS se_ejecuto
FROM information_schema.EVENTS
WHERE event_schema = 'medicita_ips'
ORDER BY event_name;

ALTER EVENT evt_marcar_inasistencias_diario DISABLE;
ALTER EVENT evt_generar_recordatorios_diario DISABLE;
ALTER EVENT evt_vencer_afiliaciones_diario DISABLE;
ALTER EVENT evt_marcar_facturas_vencidas_diario DISABLE;
ALTER EVENT evt_resumen_produccion_mensual DISABLE;

SELECT event_name, status
FROM information_schema.EVENTS
WHERE event_schema = 'medicita_ips'
ORDER BY event_name;
-- Resultado esperado: los 5 eventos en DISABLED

-- Versión "de producción" (no se ejecuta): mismos cuerpos, pero cambiando la
-- fecha de corte por CURDATE() y programados así:
--   evt_…_diario:              ON SCHEDULE EVERY 1 DAY   STARTS '2026-12-01 00:05:00'
--   evt_resumen_produccion…:   ON SCHEDULE EVERY 1 MONTH STARTS '2026-12-01 00:10:00'
