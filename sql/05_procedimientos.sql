-- 05_procedimientos.sql - MediCita IPS - Jose Miguel Sandoval
-- =====================================================================
-- MediCita IPS · 05_procedimientos.sql
-- 5 procedimientos (de menor a mayor dificultad) con sus pruebas,
-- más una demostración de TCL (START TRANSACTION, SAVEPOINT, ROLLBACK).
-- Requiere 04_funciones.sql (usa fn_medico_disponible y fn_tarifa_vigente).
-- Responsables (p_responsable) = id de system_users: 1-5 recepción,
-- 6-7 facturación, 10 SISTEMA, 11-22 médicos.
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- P-1 · sp_registrar_paciente(…, OUT p_paciente_id)
-- Registra un paciente con su teléfono principal, en una transacción:
-- o quedan los dos (paciente y teléfono) o no queda ninguno.
-- Rechaza un documento repetido para el mismo tipo.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_paciente;

DELIMITER $$

CREATE PROCEDURE sp_registrar_paciente(
    IN p_tipo_documento BIGINT,
    IN p_numero_documento VARCHAR(20),
    IN p_nombres VARCHAR(60),
    IN p_apellidos VARCHAR(60),
    IN p_fecha_nacimiento DATE,
    IN p_sexo VARCHAR(12),
    IN p_direccion VARCHAR(150),
    IN p_ciudad BIGINT,
    IN p_correo VARCHAR(120),
    IN p_telefono VARCHAR(20),
    OUT p_paciente_id BIGINT
)
BEGIN
    DECLARE v_existe INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_paciente_id = NULL;

    SELECT COUNT(*) INTO v_existe
    FROM patients
    WHERE document_type_id = p_tipo_documento
      AND document_number = p_numero_documento;

    IF v_existe > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ya existe un paciente con ese tipo y número de documento';
    END IF;

    IF p_telefono IS NULL OR TRIM(p_telefono) = '' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El teléfono principal es obligatorio';
    END IF;

    START TRANSACTION;

    INSERT INTO patients (document_type_id, document_number, first_name, last_name,
                          birth_date, sex, address, city_id, email)
    VALUES (p_tipo_documento, TRIM(p_numero_documento), TRIM(p_nombres), TRIM(p_apellidos),
            p_fecha_nacimiento, p_sexo, p_direccion, p_ciudad, NULLIF(LOWER(TRIM(p_correo)), ''));

    SET p_paciente_id = LAST_INSERT_ID();

    INSERT INTO patient_phones (patient_id, phone_number, phone_type, is_primary)
    VALUES (p_paciente_id, TRIM(p_telefono), 'CELULAR', 1);

    COMMIT;
END $$

DELIMITER ;

-- Pruebas P-1
-- Caso que funciona: paciente nuevo (queda con id 27: el 26 lo gastó el INSERT fallido de 02_dml.sql)
CALL sp_registrar_paciente(1, '1098700111', 'Sara', 'Quintero Pabón', '1999-04-12', 'FEMENINO',
                           'Calle 45 # 27-10', 1, '  Sara.Quintero@Correo.Example.com ', '3157778899', @nuevo_paciente);
SELECT @nuevo_paciente AS paciente_id;

SELECT p.id, p.document_number, CONCAT(p.first_name, ' ', p.last_name) AS paciente, p.email,
       ph.phone_number, ph.is_primary
FROM patients AS p
JOIN patient_phones AS ph ON ph.patient_id = p.id
WHERE p.id = @nuevo_paciente;

-- ⚠️ ESPERADO: ERROR 1644 (45000): Ya existe un paciente con ese tipo y número de documento
CALL sp_registrar_paciente(1, '63345120', 'Rosa', 'Repetida', '1955-03-14', 'FEMENINO',
                           'Calle 1 # 1-1', 1, NULL, '3000000000', @repetido);

-- Mismo número pero con OTRO tipo de documento (TI): sí se permite (RP-01). Queda con id 28
CALL sp_registrar_paciente(2, '63345120', 'Tomás', 'Quintero', '2013-02-02', 'MASCULINO',
                           'Carrera 27 # 45-12', 1, NULL, '3001112233', @otro_tipo);
SELECT @otro_tipo AS paciente_con_otro_tipo;

-- ---------------------------------------------------------------------
-- P-2 · sp_cancelar_cita(p_cita, p_motivo, p_responsable, p_fecha)
-- Cancela una cita PROGRAMADA o CONFIRMADA. El motivo es obligatorio y
-- debe existir en el catálogo. Rechaza citas atendidas o ya canceladas.
-- El historial lo escribe el trigger T-3 (06_triggers.sql). Como un trigger
-- no recibe parámetros, la fecha del negocio se le pasa en la variable de
-- sesión @fecha_cambio_estado (si no existe, T-3 usa NOW()).
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cancelar_cita;

DELIMITER $$

CREATE PROCEDURE sp_cancelar_cita(
    IN p_cita BIGINT,
    IN p_motivo BIGINT,
    IN p_responsable BIGINT,
    IN p_fecha DATETIME
)
BEGIN
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;
    DECLARE v_motivo_ok INT;
    DECLARE v_responsable_ok INT;

    SELECT status INTO v_estado FROM appointments WHERE id = p_cita;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cita no existe';
    END IF;

    IF p_motivo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El motivo de cancelación es obligatorio';
    END IF;

    SELECT COUNT(*) INTO v_motivo_ok
    FROM cancellation_reasons
    WHERE id = p_motivo AND is_active = TRUE;

    IF v_motivo_ok = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El motivo no existe en el catálogo de cancelación';
    END IF;

    SELECT COUNT(*) INTO v_responsable_ok FROM system_users WHERE id = p_responsable AND is_active = TRUE;
    IF v_responsable_ok = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El responsable no es un usuario activo del sistema';
    END IF;

    IF v_estado = 'ATENDIDA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede cancelar una cita ya ATENDIDA';
    ELSEIF v_estado = 'CANCELADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La cita ya está CANCELADA';
    ELSEIF v_estado NOT IN ('PROGRAMADA', 'CONFIRMADA') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se cancelan citas PROGRAMADA o CONFIRMADA';
    END IF;

    SET @fecha_cambio_estado = IFNULL(p_fecha, NOW());

    UPDATE appointments
    SET status = 'CANCELADA',
        cancellation_reason_id = p_motivo,
        updated_by = p_responsable
    WHERE id = p_cita;

    SET @fecha_cambio_estado = NULL;
END $$

DELIMITER ;

-- Pruebas P-2
-- Caso que funciona, dentro de una transacción que luego se deshace (TCL):
-- la cancelación definitiva se prueba en 06_triggers.sql, cuando ya exista T-3.
START TRANSACTION;
CALL sp_cancelar_cita(183, 2, 5, '2026-11-29 10:00:00');   -- cita 183: PROGRAMADA del 3-dic
SELECT id, status, cancellation_reason_id, updated_by FROM appointments WHERE id = 183;
-- Resultado esperado: 183 | CANCELADA | 2 | 5
ROLLBACK;
SELECT id, status, cancellation_reason_id FROM appointments WHERE id = 183;
-- Resultado esperado: 183 | PROGRAMADA | NULL (el ROLLBACK deshizo la cancelación)

-- ⚠️ ESPERADO: ERROR 1644 (45000): El motivo de cancelación es obligatorio
CALL sp_cancelar_cita(183, NULL, 5, '2026-11-29 10:00:00');

-- ⚠️ ESPERADO: ERROR 1644 (45000): El motivo no existe en el catálogo de cancelación
CALL sp_cancelar_cita(183, 99, 5, '2026-11-29 10:00:00');

-- ⚠️ ESPERADO: ERROR 1644 (45000): No se puede cancelar una cita ya ATENDIDA
CALL sp_cancelar_cita(1, 1, 5, '2026-11-29 10:00:00');

-- ⚠️ ESPERADO: ERROR 1644 (45000): La cita ya está CANCELADA
CALL sp_cancelar_cita(180, 1, 5, '2026-11-29 10:00:00');

-- ---------------------------------------------------------------------
-- P-3 · sp_agendar_cita(p_paciente, p_medico, p_especialidad, p_consultorio,
--                        p_tipo_cita, p_inicio, p_responsable, OUT p_cita_id)
-- Valida, cada una con su mensaje:
--   1. que el médico tenga la especialidad;
--   2. que atienda en la sede del consultorio;
--   3. que esté disponible (fn_medico_disponible: horario, novedades y cruces);
--   4. que el consultorio esté libre.
-- La cita nace PROGRAMADA y su primera fila del historial (NULL → PROGRAMADA)
-- se guarda en la misma transacción.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_agendar_cita;

DELIMITER $$

CREATE PROCEDURE sp_agendar_cita(
    IN p_paciente BIGINT,
    IN p_medico BIGINT,
    IN p_especialidad BIGINT,
    IN p_consultorio BIGINT,
    IN p_tipo_cita BIGINT,
    IN p_inicio DATETIME,
    IN p_responsable BIGINT,
    OUT p_cita_id BIGINT
)
BEGIN
    DECLARE v_existe INT;
    DECLARE v_duracion INT DEFAULT NULL;
    DECLARE v_sede BIGINT DEFAULT NULL;
    DECLARE v_fin DATETIME;
    DECLARE v_ocupado INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET p_cita_id = NULL;

    -- Datos básicos
    SELECT COUNT(*) INTO v_existe FROM patients WHERE id = p_paciente;
    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El paciente no existe';
    END IF;

    SELECT COUNT(*) INTO v_existe FROM doctors WHERE id = p_medico AND is_active = TRUE;
    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El médico no existe o está inactivo';
    END IF;

    SELECT duration_minutes INTO v_duracion FROM appointment_types WHERE id = p_tipo_cita;
    IF v_duracion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El tipo de cita no existe';
    END IF;

    SELECT site_id INTO v_sede FROM offices WHERE id = p_consultorio AND is_active = TRUE;
    IF v_sede IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El consultorio no existe o está fuera de servicio';
    END IF;

    -- 1. El médico tiene esa especialidad
    SELECT COUNT(*) INTO v_existe
    FROM doctor_specialties
    WHERE doctor_id = p_medico AND specialty_id = p_especialidad;
    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El médico no tiene esa especialidad';
    END IF;

    -- 2. El médico atiende en la sede del consultorio
    SELECT COUNT(*) INTO v_existe
    FROM doctor_sites
    WHERE doctor_id = p_medico AND site_id = v_sede;
    IF v_existe = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El médico no atiende en la sede de ese consultorio';
    END IF;

    -- 3. El médico está disponible (horario, novedades y cruces con sus citas)
    IF fn_medico_disponible(p_medico, p_inicio, v_duracion) = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El médico no está disponible: fuera de horario, con novedad o con otra cita a esa hora';
    END IF;

    -- 4. El consultorio está libre (ninguna cita no cancelada que se cruce)
    SET v_fin = DATE_ADD(p_inicio, INTERVAL v_duracion MINUTE);

    SELECT COUNT(*) INTO v_ocupado
    FROM appointments AS a
    JOIN appointment_types AS t ON t.id = a.appointment_type_id
    WHERE a.office_id = p_consultorio
      AND a.status <> 'CANCELADA'
      AND a.start_at < v_fin
      AND DATE_ADD(a.start_at, INTERVAL t.duration_minutes MINUTE) > p_inicio;
    IF v_ocupado > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El consultorio ya tiene una cita en ese horario';
    END IF;

    START TRANSACTION;

    INSERT INTO appointments (patient_id, doctor_id, specialty_id, office_id, appointment_type_id,
                              start_at, status, created_by, created_at)
    VALUES (p_paciente, p_medico, p_especialidad, p_consultorio, p_tipo_cita,
            p_inicio, 'PROGRAMADA', p_responsable, NOW());

    SET p_cita_id = LAST_INSERT_ID();

    INSERT INTO appointment_status_history (appointment_id, previous_status, new_status, changed_at, changed_by)
    VALUES (p_cita_id, NULL, 'PROGRAMADA', NOW(), p_responsable);

    COMMIT;
END $$

DELIMITER ;

-- Pruebas P-3
-- Caso que funciona 1: Laura (3) con la doctora Rojas (4), medicina general (1),
-- consultorio 202 de Cañaveral (5), control de 20 min (2), martes 1-dic 11:00
CALL sp_agendar_cita(3, 4, 1, 5, 2, '2026-12-01 11:00:00', 2, @cita_1);

-- Caso que funciona 2: Gloria (13) con la doctora Salazar (1), medicina interna (2),
-- consultorio 101 de Cabecera (1), control de 20 min (4), lunes 7-dic 09:00
CALL sp_agendar_cita(13, 1, 2, 1, 4, '2026-12-07 09:00:00', 1, @cita_2);

SELECT a.id, a.start_at, a.status, CONCAT(d.first_name, ' ', d.last_name) AS medico, o.code AS consultorio
FROM appointments AS a
JOIN doctors AS d ON d.id = a.doctor_id
JOIN offices AS o ON o.id = a.office_id
WHERE a.id IN (@cita_1, @cita_2);

SELECT appointment_id, previous_status, new_status, changed_by
FROM appointment_status_history
WHERE appointment_id IN (@cita_1, @cita_2);
-- Resultado esperado: dos filas NULL → PROGRAMADA

-- ⚠️ ESPERADO: ERROR 1644 (45000): El médico no tiene esa especialidad (Rojas no es cardióloga)
CALL sp_agendar_cita(3, 4, 6, 5, 2, '2026-12-01 11:30:00', 2, @falla);

-- ⚠️ ESPERADO: ERROR 1644 (45000): El médico no atiende en la sede de ese consultorio (Rojas no atiende en Cabecera)
CALL sp_agendar_cita(3, 4, 1, 1, 2, '2026-12-01 11:30:00', 2, @falla);

-- ⚠️ ESPERADO: ERROR 1644 (45000): El médico no está disponible: fuera de horario, con novedad o con otra cita a esa hora
CALL sp_agendar_cita(3, 4, 1, 5, 2, '2026-12-01 07:00:00', 2, @falla);

-- ⚠️ ESPERADO: ERROR 1644 (45000): El médico no está disponible… (Arenas está de vacaciones el 7-dic)
CALL sp_agendar_cita(5, 5, 4, 6, 3, '2026-12-07 14:00:00', 2, @falla);

-- ⚠️ ESPERADO: ERROR 1644 (45000): El consultorio ya tiene una cita en ese horario
-- (el doctor Méndez está libre el lunes 7-dic a las 09:00, pero el consultorio 101 ya lo ocupa la cita de Salazar)
CALL sp_agendar_cita(9, 3, 1, 1, 2, '2026-12-07 09:00:00', 1, @falla);

-- ---------------------------------------------------------------------
-- P-4 · sp_facturar_atencion(p_atencion, p_fecha, OUT p_factura_id)
-- Factura una atención en UNA transacción ("todo o nada"):
--   1. crea la factura;
--   2. un renglón por cada servicio prestado con la tarifa vigente el día de
--      la ATENCIÓN (fn_tarifa_vigente), no la de hoy;
--   3. calcula la parte del paciente con el copago del plan vigente ese día,
--      o 100 % si no tiene afiliación vigente (PARTICULAR).
-- Si cualquier paso falla, el EXIT HANDLER hace ROLLBACK: no queda nada.
-- Rechaza facturar dos veces la misma atención.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_facturar_atencion;

DELIMITER $$

CREATE PROCEDURE sp_facturar_atencion(
    IN p_atencion BIGINT,
    IN p_fecha DATE,
    OUT p_factura_id BIGINT
)
BEGIN
    DECLARE v_fecha_atencion DATE DEFAULT NULL;
    DECLARE v_paciente BIGINT;
    DECLARE v_ya_facturada INT;
    DECLARE v_servicios INT;
    DECLARE v_afiliacion BIGINT DEFAULT NULL;
    DECLARE v_plan BIGINT DEFAULT NULL;
    DECLARE v_copago DECIMAL(5,2);
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_parte_paciente DECIMAL(12,2);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_factura_id = NULL;
        RESIGNAL;
    END;

    SET p_factura_id = NULL;

    -- Validaciones
    SELECT DATE(at.started_at), ap.patient_id INTO v_fecha_atencion, v_paciente
    FROM attentions AS at
    JOIN appointments AS ap ON ap.id = at.appointment_id
    WHERE at.id = p_atencion;

    IF v_fecha_atencion IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La atención no existe';
    END IF;

    SELECT COUNT(*) INTO v_ya_facturada FROM invoices WHERE attention_id = p_atencion;
    IF v_ya_facturada > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La atención ya tiene factura: no se factura dos veces';
    END IF;

    SELECT COUNT(*) INTO v_servicios FROM attention_procedures WHERE attention_id = p_atencion;
    IF v_servicios = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La atención no tiene servicios para facturar';
    END IF;

    IF p_fecha < v_fecha_atencion THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de la factura no puede ser anterior a la atención';
    END IF;

    -- Plan vigente el día de la atención (por fechas); sin afiliación → PARTICULAR
    SELECT af.id, af.plan_id INTO v_afiliacion, v_plan
    FROM affiliations AS af
    WHERE af.patient_id = v_paciente
      AND af.start_date <= v_fecha_atencion
      AND (af.end_date IS NULL OR af.end_date >= v_fecha_atencion)
    ORDER BY af.start_date DESC
    LIMIT 1;

    IF v_plan IS NULL THEN
        SELECT id INTO v_plan FROM plans WHERE name = 'PARTICULAR';
    END IF;

    SELECT copay_percentage INTO v_copago FROM plans WHERE id = v_plan;

    START TRANSACTION;

    -- Paso 1: la factura (los montos se calculan en el paso 3)
    INSERT INTO invoices (invoice_number, attention_id, affiliation_id, issued_at, copay_percentage,
                          total_amount, patient_amount, insurer_amount, status)
    VALUES (CONCAT('FE-', LPAD((SELECT IFNULL(MAX(i.id), 0) + 1 FROM invoices AS i), 6, '0')),
            p_atencion, v_afiliacion, p_fecha, v_copago, 0, 0, 0, 'PENDIENTE');

    SET p_factura_id = LAST_INSERT_ID();

    -- Paso 2: un renglón por servicio con el precio COPIADO del día de la atención.
    -- Si algún servicio no tiene tarifa, fn_tarifa_vigente lanza el error y el handler deshace todo.
    INSERT INTO invoice_items (invoice_id, cups_service_id, quantity, unit_price)
    SELECT p_factura_id, apr.cups_service_id, apr.quantity,
           fn_tarifa_vigente(apr.cups_service_id, v_plan, v_fecha_atencion)
    FROM attention_procedures AS apr
    WHERE apr.attention_id = p_atencion;

    -- Paso 3: totales y reparto paciente / aseguradora
    SELECT SUM(quantity * unit_price) INTO v_total
    FROM invoice_items
    WHERE invoice_id = p_factura_id;

    SET v_parte_paciente = ROUND(v_total * v_copago / 100, 2);

    UPDATE invoices
    SET total_amount = v_total,
        patient_amount = v_parte_paciente,
        insurer_amount = v_total - v_parte_paciente
    WHERE id = p_factura_id;

    COMMIT;
END $$

DELIMITER ;

-- Pruebas P-4
-- Caso que funciona 1: atención 121 de Laura (3), del 26-nov, plan CONTRIBUTIVO (copago 10 %)
CALL sp_facturar_atencion(121, '2026-11-26', @factura_1);

SELECT i.id, i.invoice_number, i.attention_id, i.total_amount, i.copay_percentage,
       i.patient_amount, i.insurer_amount, i.status
FROM invoices AS i
WHERE i.id = @factura_1;

SELECT ii.invoice_id, cs.cups_code, ii.quantity, ii.unit_price
FROM invoice_items AS ii
JOIN cups_services AS cs ON cs.id = ii.cups_service_id
WHERE ii.invoice_id = @factura_1;
-- Resultado esperado: consulta de control 890301 a 38000.00 (tarifa CONTRIBUTIVO desde el 1-nov);
-- paciente 3800.00 y aseguradora 34200.00

-- ⚠️ ESPERADO: ERROR 1644 (45000): La atención ya tiene factura: no se factura dos veces
CALL sp_facturar_atencion(121, '2026-11-27', @factura_repetida);

-- ⚠️ ESPERADO: ERROR 1644 (45000): La atención no existe
CALL sp_facturar_atencion(999, '2026-11-27', @factura_falla);

-- Prueba del "todo o nada": a la atención 123 (particular) se le agrega un servicio
-- que todavía no tiene tarifa. La factura y su primer renglón alcanzan a insertarse,
-- pero el segundo renglón falla y el ROLLBACK del handler borra todo.
INSERT INTO cups_services (cups_code, name) VALUES ('869601', 'Retiro de puntos de sutura');
INSERT INTO attention_procedures (attention_id, cups_service_id, quantity)
VALUES (123, (SELECT id FROM cups_services WHERE cups_code = '869601'), 1);

-- ⚠️ ESPERADO: ERROR 1644 (45000): No hay tarifa vigente para el servicio 11 en el plan 4 el día 2026-11-27
CALL sp_facturar_atencion(123, '2026-11-27', @factura_2);

SELECT COUNT(*) AS facturas_de_la_atencion_123 FROM invoices WHERE attention_id = 123;
-- Resultado esperado: 0 (no quedó ni la factura ni sus renglones)

-- Se quita el servicio sin tarifa y ahora sí se factura (paciente particular: paga el 100 %)
DELETE FROM attention_procedures
WHERE attention_id = 123 AND cups_service_id = (SELECT id FROM cups_services WHERE cups_code = '869601');

CALL sp_facturar_atencion(123, '2026-11-27', @factura_2);

SELECT i.invoice_number, i.affiliation_id, i.copay_percentage, i.total_amount,
       i.patient_amount, i.insurer_amount
FROM invoices AS i
WHERE i.id = @factura_2;
-- Resultado esperado: affiliation_id NULL, copago 100.00, insurer_amount 0.00

-- ---------------------------------------------------------------------
-- P-5 · sp_reporte_produccion(p_desde, p_hasta)
-- Con un CURSOR recorre los médicos y arma, para cada uno: número de
-- atenciones, valor facturado (sin anuladas) y promedio por atención.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_reporte_produccion;

DELIMITER $$

CREATE PROCEDURE sp_reporte_produccion(IN p_desde DATE, IN p_hasta DATE)
BEGIN
    DECLARE v_fin_cursor BOOLEAN DEFAULT FALSE;
    DECLARE v_medico_id BIGINT;
    DECLARE v_medico VARCHAR(130);
    DECLARE v_atenciones INT;
    DECLARE v_facturado DECIMAL(12,2);

    -- 1. El cursor: la lista de médicos que se va a recorrer
    DECLARE cur_medicos CURSOR FOR
        SELECT d.id, CONCAT(d.first_name, ' ', d.last_name)
        FROM doctors AS d
        ORDER BY d.last_name, d.first_name;

    -- 2. Cuando el cursor ya no tenga filas, se enciende la bandera
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_fin_cursor = TRUE;

    IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta < p_desde THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rango de fechas no válido';
    END IF;

    DROP TEMPORARY TABLE IF EXISTS tmp_reporte_produccion;
    CREATE TEMPORARY TABLE tmp_reporte_produccion (
        doctor_id BIGINT,
        medico VARCHAR(130),
        atenciones INT,
        valor_facturado DECIMAL(12,2),
        promedio_por_atencion DECIMAL(12,2)
    );

    OPEN cur_medicos;

    leer_medicos: LOOP
        FETCH cur_medicos INTO v_medico_id, v_medico;
        IF v_fin_cursor THEN
            LEAVE leer_medicos;
        END IF;

        SELECT COUNT(*) INTO v_atenciones
        FROM attentions AS at
        JOIN appointments AS ap ON ap.id = at.appointment_id
        WHERE ap.doctor_id = v_medico_id
          AND DATE(at.started_at) BETWEEN p_desde AND p_hasta;

        SELECT IFNULL(SUM(i.total_amount), 0) INTO v_facturado
        FROM invoices AS i
        JOIN attentions AS at ON at.id = i.attention_id
        JOIN appointments AS ap ON ap.id = at.appointment_id
        WHERE ap.doctor_id = v_medico_id
          AND i.status <> 'ANULADA'
          AND DATE(at.started_at) BETWEEN p_desde AND p_hasta;

        INSERT INTO tmp_reporte_produccion
        VALUES (v_medico_id, v_medico, v_atenciones, v_facturado,
                IF(v_atenciones = 0, 0, ROUND(v_facturado / v_atenciones, 2)));
    END LOOP;

    CLOSE cur_medicos;

    SELECT doctor_id, medico, atenciones, valor_facturado, promedio_por_atencion
    FROM tmp_reporte_produccion
    ORDER BY valor_facturado DESC, medico;

    DROP TEMPORARY TABLE IF EXISTS tmp_reporte_produccion;
END $$

DELIMITER ;

-- Pruebas P-5
CALL sp_reporte_produccion('2026-11-01', '2026-11-30');
-- Resultado esperado: una fila por cada uno de los 12 médicos (Duarte y Cárdenas pueden salir en 0)

-- ⚠️ ESPERADO: ERROR 1644 (45000): Rango de fechas no válido
CALL sp_reporte_produccion('2026-11-30', '2026-11-01');

-- ---------------------------------------------------------------------
-- Demostración TCL: SAVEPOINT y ROLLBACK TO SAVEPOINT
-- El paciente 4 actualiza sus datos de contacto: el correo sí se guarda,
-- pero el teléfono nuevo estaba mal escrito y solo se deshace esa parte.
-- ---------------------------------------------------------------------
SELECT p.id, p.email,
       (SELECT COUNT(*) FROM patient_phones AS ph WHERE ph.patient_id = p.id) AS telefonos
FROM patients AS p
WHERE p.id = 4;

START TRANSACTION;

UPDATE patients SET email = 'gustavo.prada@correo.example.com' WHERE id = 4;

SAVEPOINT sp_correo_guardado;

INSERT INTO patient_phones (patient_id, phone_number, phone_type, is_primary)
VALUES (4, '31X-ERROR', 'CELULAR', NULL);

ROLLBACK TO SAVEPOINT sp_correo_guardado;   -- deshace solo el teléfono

COMMIT;                                     -- confirma el correo

SELECT p.id, p.email,
       (SELECT COUNT(*) FROM patient_phones AS ph WHERE ph.patient_id = p.id) AS telefonos
FROM patients AS p
WHERE p.id = 4;
-- Resultado esperado: correo nuevo y los mismos 2 teléfonos que tenía (el mal escrito no quedó)

-- Revisión: deben aparecer los 5 procedimientos
SHOW PROCEDURE STATUS WHERE Db = 'medicita_ips';
