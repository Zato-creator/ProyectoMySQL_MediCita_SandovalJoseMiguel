-- 06_triggers.sql - MediCita IPS - Jose Miguel Sandoval
-- =====================================================================
-- MediCita IPS · 06_triggers.sql
-- 5 triggers del enunciado (T-1 a T-5, de menor a mayor dificultad) y
-- 5 triggers de apoyo para reglas que comparan varias filas.
-- Requiere 04_funciones.sql (T-4 usa fn_saldo_factura) y 05 (T-3 se prueba
-- con sp_cancelar_cita).
--
-- ⚠️ Error 1442: un trigger NO puede modificar la tabla que lo disparó.
--   · T-3 se dispara en appointments y escribe en OTRA tabla
--     (appointment_status_history).
--   · T-4 se dispara en payments y actualiza OTRA tabla (invoices).
--   Por eso ninguno de los dos cae en el 1442.
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- T-1 · trg_vital_signs_before_insert
-- Rechaza signos vitales imposibles: sistólica 60–260, diastólica 30–160
-- y menor que la sistólica, temperatura 30–45 °C, frecuencia 20–250.
-- Es BEFORE porque valida antes de guardar. Los CHECK del DDL también
-- protegen, pero el trigger devuelve un mensaje claro en español.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_vital_signs_before_insert;

DELIMITER $$

CREATE TRIGGER trg_vital_signs_before_insert
BEFORE INSERT ON vital_signs
FOR EACH ROW
BEGIN
    IF NEW.systolic_bp NOT BETWEEN 60 AND 260 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Presión sistólica fuera de rango (60 a 260 mmHg)';
    END IF;

    IF NEW.diastolic_bp NOT BETWEEN 30 AND 160 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Presión diastólica fuera de rango (30 a 160 mmHg)';
    END IF;

    IF NEW.diastolic_bp >= NEW.systolic_bp THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La presión diastólica debe ser menor que la sistólica';
    END IF;

    IF NEW.temperature_c NOT BETWEEN 30 AND 45 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Temperatura fuera de rango (30 a 45 °C)';
    END IF;

    IF NEW.heart_rate NOT BETWEEN 20 AND 250 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Frecuencia cardíaca fuera de rango (20 a 250 lpm)';
    END IF;
END $$

DELIMITER ;

-- Pruebas T-1 (atención 121: Laura, 26-nov)
INSERT INTO vital_signs (attention_id, measured_at, systolic_bp, diastolic_bp, heart_rate,
                         temperature_c, weight_kg, height_cm)
VALUES (121, '2026-11-26 14:20:00', 118, 76, 72, 36.6, 61.5, 164.0);

SELECT attention_id, measured_at, systolic_bp, diastolic_bp, temperature_c
FROM vital_signs WHERE attention_id = 121 ORDER BY id;

-- ⚠️ ESPERADO: ERROR 1644 (45000): Presión sistólica fuera de rango (60 a 260 mmHg)
INSERT INTO vital_signs (attention_id, measured_at, systolic_bp, diastolic_bp, heart_rate,
                         temperature_c, weight_kg, height_cm)
VALUES (121, '2026-11-26 14:25:00', 1200, 80, 72, 36.6, 61.5, 164.0);

-- ⚠️ ESPERADO: ERROR 1644 (45000): Temperatura fuera de rango (30 a 45 °C)
INSERT INTO vital_signs (attention_id, measured_at, systolic_bp, diastolic_bp, heart_rate,
                         temperature_c, weight_kg, height_cm)
VALUES (121, '2026-11-26 14:25:00', 120, 80, 72, 5.0, 61.5, 164.0);

-- ⚠️ ESPERADO: ERROR 1644 (45000): La presión diastólica debe ser menor que la sistólica
INSERT INTO vital_signs (attention_id, measured_at, systolic_bp, diastolic_bp, heart_rate,
                         temperature_c, weight_kg, height_cm)
VALUES (121, '2026-11-26 14:25:00', 90, 95, 72, 36.6, 61.5, 164.0);

-- ---------------------------------------------------------------------
-- T-2 · trg_invoices_before_delete
-- Las facturas nunca se borran (la DIAN y la auditoría las piden): se anulan
-- con sp_anular_factura (08_dcl.sql).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_invoices_before_delete;

DELIMITER $$

CREATE TRIGGER trg_invoices_before_delete
BEFORE DELETE ON invoices
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Las facturas no se borran: anúlela';
END $$

DELIMITER ;

-- Pruebas T-2
-- ⚠️ ESPERADO: ERROR 1644 (45000): Las facturas no se borran: anúlela
DELETE FROM invoices WHERE id = 5;

SELECT id, invoice_number, status FROM invoices WHERE id = 5;
-- Resultado esperado: la factura 5 sigue ahí (ANULADA)

-- ---------------------------------------------------------------------
-- T-3 · trg_appointments_after_update
-- Cuando cambia el estado de una cita, guarda en el historial el estado
-- anterior, el nuevo, la fecha y el responsable.
--   · responsable: NEW.updated_by (lo llenan los procedimientos y E-1);
--     si viene vacío, se usa el usuario SISTEMA.
--   · fecha: @fecha_cambio_estado (fecha del negocio que deja el procedimiento
--     o el evento); si no existe, NOW().
-- Es AFTER porque registra algo que ya pasó, y escribe en otra tabla (sin 1442).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_appointments_after_update;

DELIMITER $$

CREATE TRIGGER trg_appointments_after_update
AFTER UPDATE ON appointments
FOR EACH ROW
BEGIN
    DECLARE v_responsable BIGINT;

    IF NOT (OLD.status <=> NEW.status) THEN
        SET v_responsable = NEW.updated_by;

        IF v_responsable IS NULL THEN
            SELECT id INTO v_responsable FROM system_users WHERE role = 'SISTEMA' ORDER BY id LIMIT 1;
        END IF;

        INSERT INTO appointment_status_history (appointment_id, previous_status, new_status,
                                                changed_at, changed_by, cancellation_reason_id)
        VALUES (NEW.id, OLD.status, NEW.status,
                IFNULL(@fecha_cambio_estado, NOW()), v_responsable,
                IF(NEW.status = 'CANCELADA', NEW.cancellation_reason_id, NULL));
    END IF;
END $$

DELIMITER ;

-- Pruebas T-3
-- 1. Cancelación definitiva con el procedimiento: cita 183 (PROGRAMADA del 3-dic), motivo Viaje (2), call.center (5)
CALL sp_cancelar_cita(183, 2, 5, '2026-11-29 10:00:00');

-- 2. El paciente confirma la cita 173 (cambio directo hecho por un administrador).
--    Se deja la fecha del negocio en la variable de sesión que lee el trigger
SET @fecha_cambio_estado = '2026-11-29 16:00:00';
UPDATE appointments SET status = 'CONFIRMADA', updated_by = 5 WHERE id = 173;
SET @fecha_cambio_estado = NULL;

-- 3. Un UPDATE que NO cambia el estado: el trigger se dispara, pero no registra nada
UPDATE appointments SET office_id = office_id WHERE id = 173;

SELECT h.appointment_id, h.previous_status, h.new_status, h.changed_at,
       u.username AS responsable, h.cancellation_reason_id AS motivo
FROM appointment_status_history AS h
JOIN system_users AS u ON u.id = h.changed_by
WHERE h.appointment_id IN (173, 183)
ORDER BY h.appointment_id, h.id;
-- Resultado esperado: la 183 termina en PROGRAMADA → CANCELADA (2026-11-29 10:00, call.center, motivo 2)
-- y la 173 en PROGRAMADA → CONFIRMADA (2026-11-29 16:00). El tercer UPDATE no dejó fila.

-- ---------------------------------------------------------------------
-- T-4 · trg_payments_after_insert
-- Después de cada abono actualiza el estado de la factura:
-- PAGADA si el saldo llega a 0; PARCIAL si aún hay saldo.
-- Decisión: una factura VENCIDA que recibe un abono parcial sigue VENCIDA
-- (la mora no desaparece por abonar una parte); si se paga completa, PAGADA.
-- Se dispara en payments y actualiza invoices (otra tabla: sin 1442).
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_payments_after_insert;

DELIMITER $$

CREATE TRIGGER trg_payments_after_insert
AFTER INSERT ON payments
FOR EACH ROW
BEGIN
    DECLARE v_saldo DECIMAL(12,2);

    SET v_saldo = fn_saldo_factura(NEW.invoice_id);

    IF v_saldo <= 0 THEN
        UPDATE invoices SET status = 'PAGADA' WHERE id = NEW.invoice_id;
    ELSE
        UPDATE invoices SET status = 'PARCIAL'
        WHERE id = NEW.invoice_id AND status <> 'VENCIDA';
    END IF;
END $$

DELIMITER ;

-- ---------------------------------------------------------------------
-- Trigger de apoyo · trg_payments_before_insert
-- Regla de varias filas: no se abona a una factura ANULADA o PAGADA, ni
-- por más del saldo. (Va aquí porque T-4 depende de que el abono sea válido.)
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_payments_before_insert;

DELIMITER $$

CREATE TRIGGER trg_payments_before_insert
BEFORE INSERT ON payments
FOR EACH ROW
BEGIN
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;

    SELECT status INTO v_estado FROM invoices WHERE id = NEW.invoice_id;

    IF v_estado IN ('ANULADA', 'PAGADA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se pueden registrar abonos a una factura ANULADA o PAGADA';
    END IF;

    IF NEW.amount > fn_saldo_factura(NEW.invoice_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El abono supera el saldo de la factura';
    END IF;
END $$

DELIMITER ;

-- Pruebas T-4 (factura 117: la que creó sp_facturar_atencion, total 38.000, PENDIENTE)
INSERT INTO payments (invoice_id, payment_method_id, amount, paid_at, reference, received_by)
VALUES (117, 1, 10000, '2026-11-28 09:00:00', 'REC-00117-1', 6);
SELECT id, status, fn_saldo_factura(id) AS saldo FROM invoices WHERE id = 117;
-- Resultado esperado: 117 | PARCIAL | 28000.00

INSERT INTO payments (invoice_id, payment_method_id, amount, paid_at, reference, received_by)
VALUES (117, 5, 28000, '2026-11-29 11:00:00', 'REC-00117-2', 6);
SELECT id, status, fn_saldo_factura(id) AS saldo FROM invoices WHERE id = 117;
-- Resultado esperado: 117 | PAGADA | 0.00

-- La factura 1 está VENCIDA: un abono parcial no le quita la mora
INSERT INTO payments (invoice_id, payment_method_id, amount, paid_at, reference, received_by)
VALUES (1, 4, 20000, '2026-11-29 15:00:00', 'REC-00001-1', 7);
SELECT id, status, fn_saldo_factura(id) AS saldo FROM invoices WHERE id = 1;
-- Resultado esperado: 1 | VENCIDA | 64000.00

-- ⚠️ ESPERADO: ERROR 1644 (45000): No se pueden registrar abonos a una factura ANULADA o PAGADA
INSERT INTO payments (invoice_id, payment_method_id, amount, paid_at, reference, received_by)
VALUES (5, 1, 1000, '2026-11-29 15:00:00', 'REC-00005-1', 6);

-- ⚠️ ESPERADO: ERROR 1644 (45000): El abono supera el saldo de la factura
INSERT INTO payments (invoice_id, payment_method_id, amount, paid_at, reference, received_by)
VALUES (1, 1, 999999, '2026-11-29 15:00:00', 'REC-00001-2', 6);

-- ---------------------------------------------------------------------
-- T-5 · trg_prescription_items_before_insert
-- Rechaza formular un medicamento cuyo PRINCIPIO ACTIVO está entre las
-- alergias del paciente de esa fórmula. Camino para llegar al paciente:
-- prescription_items → prescriptions → attentions → appointments → paciente.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_prescription_items_before_insert;

DELIMITER $$

CREATE TRIGGER trg_prescription_items_before_insert
BEFORE INSERT ON prescription_items
FOR EACH ROW
BEGIN
    DECLARE v_paciente BIGINT;
    DECLARE v_principio VARCHAR(80) DEFAULT NULL;
    DECLARE v_mensaje VARCHAR(200);

    SELECT ap.patient_id INTO v_paciente
    FROM prescriptions AS pr
    JOIN attentions AS at ON at.id = pr.attention_id
    JOIN appointments AS ap ON ap.id = at.appointment_id
    WHERE pr.id = NEW.prescription_id;

    SELECT ai.name INTO v_principio
    FROM medications AS m
    JOIN active_ingredients AS ai ON ai.id = m.active_ingredient_id
    JOIN patient_allergies AS pa ON pa.active_ingredient_id = m.active_ingredient_id
    WHERE m.id = NEW.medication_id
      AND pa.patient_id = v_paciente
    LIMIT 1;

    IF v_principio IS NOT NULL THEN
        SET v_mensaje = CONCAT('El paciente es alérgico al principio activo ', v_principio,
                               ': no se puede formular este medicamento');
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;
END $$

DELIMITER ;

-- Pruebas T-5: Laura (paciente 3) es alérgica al IBUPROFENO. Fórmula de su atención 121
INSERT INTO prescriptions (attention_id, issued_at, notes)
VALUES (121, '2026-11-26 14:30:00', 'Dolor lumbar');
SET @formula = LAST_INSERT_ID();

-- ⚠️ ESPERADO: ERROR 1644 (45000): El paciente es alérgico al principio activo Ibuprofeno: no se puede formular este medicamento
INSERT INTO prescription_items (prescription_id, medication_id, dose, frequency, duration_days)
VALUES (@formula, 1, '1 tableta', 'Cada 8 horas', 5);      -- Advil (ibuprofeno)

-- Otra MARCA del mismo principio activo también se rechaza: la alergia es contra el principio, no la marca
-- ⚠️ ESPERADO: ERROR 1644 (45000): El paciente es alérgico al principio activo Ibuprofeno: no se puede formular este medicamento
INSERT INTO prescription_items (prescription_id, medication_id, dose, frequency, duration_days)
VALUES (@formula, 2, '1 tableta', 'Cada 8 horas', 5);      -- Ibuprofeno MK

-- Caso que funciona: Dolex (acetaminofén)
INSERT INTO prescription_items (prescription_id, medication_id, dose, frequency, duration_days)
VALUES (@formula, 3, '1 tableta', 'Cada 8 horas', 5);

SELECT pi.prescription_id, m.commercial_name, ai.name AS principio_activo, pi.dose, pi.frequency, pi.duration_days
FROM prescription_items AS pi
JOIN medications AS m ON m.id = pi.medication_id
JOIN active_ingredients AS ai ON ai.id = m.active_ingredient_id
WHERE pi.prescription_id = @formula;

-- ---------------------------------------------------------------------
-- Triggers de apoyo para reglas de varias filas (ver README)
-- ---------------------------------------------------------------------

-- Solo una afiliación ACTIVA por paciente (RP-10 corregida), al insertar…
DROP TRIGGER IF EXISTS trg_affiliations_before_insert;

DELIMITER $$

CREATE TRIGGER trg_affiliations_before_insert
BEFORE INSERT ON affiliations
FOR EACH ROW
BEGIN
    DECLARE v_activas INT;

    IF NEW.status = 'ACTIVA' THEN
        SELECT COUNT(*) INTO v_activas
        FROM affiliations
        WHERE patient_id = NEW.patient_id AND status = 'ACTIVA';

        IF v_activas > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'El paciente ya tiene una afiliación ACTIVA: inactívela antes de registrar otra';
        END IF;
    END IF;
END $$

DELIMITER ;

-- … y al reactivar una afiliación vieja
DROP TRIGGER IF EXISTS trg_affiliations_before_update;

DELIMITER $$

CREATE TRIGGER trg_affiliations_before_update
BEFORE UPDATE ON affiliations
FOR EACH ROW
BEGIN
    DECLARE v_activas INT;

    IF NEW.status = 'ACTIVA' AND OLD.status <> 'ACTIVA' THEN
        SELECT COUNT(*) INTO v_activas
        FROM affiliations
        WHERE patient_id = NEW.patient_id AND status = 'ACTIVA' AND id <> NEW.id;

        IF v_activas > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'El paciente ya tiene una afiliación ACTIVA: inactívela antes de registrar otra';
        END IF;
    END IF;
END $$

DELIMITER ;

-- Solo se encuestan citas ATENDIDA (la unicidad por cita ya la da el UNIQUE)
DROP TRIGGER IF EXISTS trg_surveys_before_insert;

DELIMITER $$

CREATE TRIGGER trg_surveys_before_insert
BEFORE INSERT ON surveys
FOR EACH ROW
BEGIN
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;

    SELECT status INTO v_estado FROM appointments WHERE id = NEW.appointment_id;

    IF v_estado IS NULL OR v_estado <> 'ATENDIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se encuestan citas ATENDIDA';
    END IF;
END $$

DELIMITER ;

-- Las vigencias de un mismo servicio y plan no se pueden cruzar
DROP TRIGGER IF EXISTS trg_tariffs_before_insert;

DELIMITER $$

CREATE TRIGGER trg_tariffs_before_insert
BEFORE INSERT ON tariffs
FOR EACH ROW
BEGIN
    DECLARE v_cruces INT;

    SELECT COUNT(*) INTO v_cruces
    FROM tariffs
    WHERE cups_service_id = NEW.cups_service_id
      AND plan_id = NEW.plan_id
      AND NEW.valid_from <= valid_to
      AND NEW.valid_to >= valid_from;

    IF v_cruces > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La vigencia se cruza con otra tarifa del mismo servicio y plan';
    END IF;
END $$

DELIMITER ;

-- Pruebas de los triggers de apoyo
-- ⚠️ ESPERADO: ERROR 1644 (45000): El paciente ya tiene una afiliación ACTIVA: inactívela antes de registrar otra
INSERT INTO affiliations (patient_id, insurer_id, plan_id, start_date, end_date, status)
VALUES (1, 2, 1, '2026-11-01', NULL, 'ACTIVA');

-- ⚠️ ESPERADO: ERROR 1644 (45000): El paciente ya tiene una afiliación ACTIVA: inactívela antes de registrar otra
UPDATE affiliations SET status = 'ACTIVA' WHERE id = 2;     -- la afiliación vieja del paciente 2

-- ⚠️ ESPERADO: ERROR 1644 (45000): Solo se encuestan citas ATENDIDA
INSERT INTO surveys (appointment_id, score, comment, answered_at)
VALUES (183, 5, 'Cita cancelada', '2026-11-29 12:00:00');

-- Caso que funciona: la cita 166 (ATENDIDA) aún no tenía encuesta
INSERT INTO surveys (appointment_id, score, comment, answered_at)
VALUES (166, 4, 'Me explicaron bien la fórmula', '2026-11-27 10:00:00');

-- ⚠️ ESPERADO: ERROR 1644 (45000): La vigencia se cruza con otra tarifa del mismo servicio y plan
INSERT INTO tariffs (cups_service_id, plan_id, price, valid_from, valid_to)
VALUES (1, 1, 50000, '2026-12-01', '2027-06-30');

-- Revisión: deben aparecer 10 triggers
SELECT trigger_name, action_timing, event_manipulation, event_object_table
FROM information_schema.TRIGGERS
WHERE trigger_schema = 'medicita_ips'
ORDER BY event_object_table, trigger_name;
