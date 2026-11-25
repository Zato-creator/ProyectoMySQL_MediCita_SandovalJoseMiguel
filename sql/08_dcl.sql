-- 08_dcl.sql - MediCita IPS - Jose Miguel Sandoval
-- =====================================================================
-- MediCita IPS · 08_dcl.sql
-- Roles (MySQL 8), un usuario de prueba por rol, permisos con privilegio
-- mínimo y el procedimiento de apoyo sp_anular_factura.
-- Se ejecuta con la conexión de ADMINISTRADOR (root).
-- Contraseña de práctica de todos los usuarios: Practica_2026*
-- La evidencia (acciones permitidas y denegadas de cada usuario) está al
-- final, COMENTADA, con el error real que devuelve MySQL.
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- 0. Procedimiento de apoyo: sp_anular_factura(p_factura, p_fecha, p_motivo)
-- Anula una factura con fecha y motivo (tabla invoice_cancellations).
-- Rechaza: factura que no existe, ya anulada, motivo vacío o con abonos.
-- Así facturación NUNCA cambia el estado a mano: PARCIAL y PAGADA los pone
-- T-4, VENCIDA el evento E-4 y ANULADA este procedimiento.
-- ---------------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_anular_factura;

DELIMITER $$

CREATE PROCEDURE sp_anular_factura(
    IN p_factura BIGINT,
    IN p_fecha DATETIME,
    IN p_motivo VARCHAR(200)
)
BEGIN
    DECLARE v_estado VARCHAR(20) DEFAULT NULL;
    DECLARE v_abonos INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT status INTO v_estado FROM invoices WHERE id = p_factura;

    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura no existe';
    END IF;

    IF v_estado = 'ANULADA' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La factura ya está ANULADA';
    END IF;

    IF p_motivo IS NULL OR TRIM(p_motivo) = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El motivo de anulación es obligatorio';
    END IF;

    SELECT COUNT(*) INTO v_abonos FROM payments WHERE invoice_id = p_factura;
    IF v_abonos > 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No se puede anular una factura que tiene abonos';
    END IF;

    START TRANSACTION;

    UPDATE invoices SET status = 'ANULADA' WHERE id = p_factura;

    INSERT INTO invoice_cancellations (invoice_id, cancelled_at, reason, cancelled_by)
    VALUES (p_factura, IFNULL(p_fecha, NOW()), TRIM(p_motivo), NULL);

    COMMIT;
END $$

DELIMITER ;

-- Pruebas de sp_anular_factura (como root)
CALL sp_anular_factura(82, '2026-11-29 09:00:00', 'Servicio facturado de más');
SELECT i.id, i.status, c.cancelled_at, c.reason
FROM invoices AS i
JOIN invoice_cancellations AS c ON c.invoice_id = i.id
WHERE i.id = 82;
-- Resultado esperado: 82 | ANULADA | 2026-11-29 09:00:00 | Servicio facturado de más

-- ⚠️ ESPERADO: ERROR 1644 (45000): La factura no existe
CALL sp_anular_factura(999, '2026-11-29 09:00:00', 'Prueba');
-- ⚠️ ESPERADO: ERROR 1644 (45000): La factura ya está ANULADA
CALL sp_anular_factura(5, '2026-11-29 09:00:00', 'Prueba');
-- ⚠️ ESPERADO: ERROR 1644 (45000): El motivo de anulación es obligatorio
CALL sp_anular_factura(83, '2026-11-29 09:00:00', '   ');
-- ⚠️ ESPERADO: ERROR 1644 (45000): No se puede anular una factura que tiene abonos
CALL sp_anular_factura(2, '2026-11-29 09:00:00', 'Error del plan');

-- ---------------------------------------------------------------------
-- 1. Limpieza previa (si no existen, no pasa nada). Los usuarios y roles
--    viven en el servidor: DROP DATABASE no los borra.
-- ---------------------------------------------------------------------
DROP USER IF EXISTS 'recepcion1_medicita'@'localhost', 'medico1_medicita'@'localhost',
    'facturacion1_medicita'@'localhost', 'auditor1_medicita'@'localhost', 'admin1_medicita'@'localhost';
DROP ROLE IF EXISTS 'rol_recepcion', 'rol_medico', 'rol_facturacion', 'rol_auditor', 'rol_admin_bd';

-- ---------------------------------------------------------------------
-- 2. Roles: permisos por cargo, no por persona
-- ---------------------------------------------------------------------
CREATE ROLE 'rol_recepcion', 'rol_medico', 'rol_facturacion', 'rol_auditor', 'rol_admin_bd';

-- ---- rol_recepcion ---------------------------------------------------
-- Puede: consultar pacientes, médicos, agenda y catálogos; registrar
-- pacientes; agendar y cancelar SOLO con los procedimientos.
-- No puede: ver datos clínicos ni de facturación; modificar citas directamente
-- (no tiene INSERT/UPDATE/DELETE sobre appointments).
GRANT SELECT ON medicita_ips.patients TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.patient_phones TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.emergency_contacts TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.affiliations TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.insurers TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.plans TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.document_types TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.cities TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctors TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.specialties TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_specialties TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_sites TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_schedules TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.doctor_absences TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.absence_types TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.sites TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.offices TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.appointments TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.appointment_types TO 'rol_recepcion';
GRANT SELECT ON medicita_ips.cancellation_reasons TO 'rol_recepcion';
-- Teléfonos y contactos adicionales de un paciente ya registrado
GRANT INSERT ON medicita_ips.patient_phones TO 'rol_recepcion';
GRANT INSERT ON medicita_ips.emergency_contacts TO 'rol_recepcion';
-- Operaciones controladas: los procedimientos corren con los permisos de
-- quien los creó (SQL SECURITY DEFINER), así que basta con EXECUTE
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_registrar_paciente TO 'rol_recepcion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_agendar_cita TO 'rol_recepcion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_cancelar_cita TO 'rol_recepcion';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_medico_disponible TO 'rol_recepcion';

-- ---- rol_medico ------------------------------------------------------
-- Puede: consultar pacientes y su agenda; registrar atenciones, signos
-- vitales, diagnósticos, fórmulas y laboratorio.
-- No puede: ver ni modificar facturación; borrar datos clínicos (sin DELETE).
GRANT SELECT ON medicita_ips.patients TO 'rol_medico';
GRANT SELECT ON medicita_ips.patient_phones TO 'rol_medico';
GRANT SELECT ON medicita_ips.emergency_contacts TO 'rol_medico';
GRANT SELECT ON medicita_ips.patient_allergies TO 'rol_medico';
GRANT SELECT ON medicita_ips.active_ingredients TO 'rol_medico';
GRANT SELECT ON medicita_ips.medications TO 'rol_medico';
GRANT SELECT ON medicita_ips.cie10_codes TO 'rol_medico';
GRANT SELECT ON medicita_ips.cups_services TO 'rol_medico';
GRANT SELECT ON medicita_ips.lab_exams TO 'rol_medico';
GRANT SELECT ON medicita_ips.appointments TO 'rol_medico';
GRANT SELECT ON medicita_ips.appointment_types TO 'rol_medico';
GRANT SELECT ON medicita_ips.appointment_status_history TO 'rol_medico';
GRANT SELECT ON medicita_ips.specialties TO 'rol_medico';
GRANT SELECT ON medicita_ips.doctors TO 'rol_medico';
GRANT SELECT ON medicita_ips.offices TO 'rol_medico';
GRANT SELECT ON medicita_ips.sites TO 'rol_medico';
GRANT SELECT ON medicita_ips.attentions TO 'rol_medico';
GRANT SELECT ON medicita_ips.vital_signs TO 'rol_medico';
GRANT SELECT ON medicita_ips.attention_diagnoses TO 'rol_medico';
GRANT SELECT ON medicita_ips.attention_procedures TO 'rol_medico';
GRANT SELECT ON medicita_ips.prescriptions TO 'rol_medico';
GRANT SELECT ON medicita_ips.prescription_items TO 'rol_medico';
GRANT SELECT ON medicita_ips.lab_orders TO 'rol_medico';
GRANT SELECT ON medicita_ips.lab_order_items TO 'rol_medico';
GRANT SELECT ON medicita_ips.lab_results TO 'rol_medico';
GRANT INSERT ON medicita_ips.attentions TO 'rol_medico';
GRANT INSERT ON medicita_ips.vital_signs TO 'rol_medico';
GRANT INSERT ON medicita_ips.attention_diagnoses TO 'rol_medico';
GRANT INSERT ON medicita_ips.attention_procedures TO 'rol_medico';
GRANT INSERT ON medicita_ips.prescriptions TO 'rol_medico';
GRANT INSERT ON medicita_ips.prescription_items TO 'rol_medico';
GRANT INSERT ON medicita_ips.lab_orders TO 'rol_medico';
GRANT INSERT ON medicita_ips.lab_order_items TO 'rol_medico';
GRANT INSERT ON medicita_ips.lab_results TO 'rol_medico';
GRANT INSERT ON medicita_ips.patient_allergies TO 'rol_medico';
-- Corregir la nota o la hora de cierre de su atención y el estado de una orden
GRANT UPDATE (ended_at, notes) ON medicita_ips.attentions TO 'rol_medico';
GRANT UPDATE (status) ON medicita_ips.lab_orders TO 'rol_medico';
-- Marcar la cita como ATENDIDA (el trigger T-3 deja el historial)
GRANT UPDATE (status, updated_by) ON medicita_ips.appointments TO 'rol_medico';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_edad TO 'rol_medico';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_imc TO 'rol_medico';

-- ---- rol_facturacion -------------------------------------------------
-- Puede: consultar atenciones y tarifas; facturar SOLO con el procedimiento;
-- registrar abonos; anular SOLO con sp_anular_factura.
-- No puede: ver datos clínicos (diagnósticos, fórmulas, laboratorio); cambiar
-- el estado de una factura (no tiene UPDATE sobre invoices); borrar facturas.
GRANT SELECT ON medicita_ips.patients TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.appointments TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.attentions TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.attention_procedures TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.doctors TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.specialties TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.sites TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.offices TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.cups_services TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.tariffs TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.plans TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.insurers TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.affiliations TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.invoices TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.invoice_items TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.invoice_cancellations TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.payments TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.payment_methods TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.system_users TO 'rol_facturacion';
GRANT SELECT ON medicita_ips.monthly_production_summary TO 'rol_facturacion';
GRANT INSERT ON medicita_ips.payments TO 'rol_facturacion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_facturar_atencion TO 'rol_facturacion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_anular_factura TO 'rol_facturacion';
GRANT EXECUTE ON PROCEDURE medicita_ips.sp_reporte_produccion TO 'rol_facturacion';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_saldo_factura TO 'rol_facturacion';
GRANT EXECUTE ON FUNCTION medicita_ips.fn_tarifa_vigente TO 'rol_facturacion';

-- ---- rol_auditor -----------------------------------------------------
-- Puede: LEER todo excepto los datos de contacto y el documento de los
-- pacientes. En patients se da SELECT POR COLUMNAS (sin document_number,
-- address ni email) y no se da nada sobre patient_phones ni emergency_contacts.
-- No puede: modificar nada (solo tiene SELECT).
GRANT SELECT (id, document_type_id, first_name, last_name, birth_date, sex, city_id, created_at)
    ON medicita_ips.patients TO 'rol_auditor';
GRANT SELECT ON medicita_ips.absence_types TO 'rol_auditor';
GRANT SELECT ON medicita_ips.active_ingredients TO 'rol_auditor';
GRANT SELECT ON medicita_ips.affiliations TO 'rol_auditor';
GRANT SELECT ON medicita_ips.appointment_status_history TO 'rol_auditor';
GRANT SELECT ON medicita_ips.appointment_types TO 'rol_auditor';
GRANT SELECT ON medicita_ips.appointments TO 'rol_auditor';
GRANT SELECT ON medicita_ips.attention_diagnoses TO 'rol_auditor';
GRANT SELECT ON medicita_ips.attention_procedures TO 'rol_auditor';
GRANT SELECT ON medicita_ips.attentions TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cancellation_reasons TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cie10_codes TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cities TO 'rol_auditor';
GRANT SELECT ON medicita_ips.cups_services TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_absences TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_schedules TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_sites TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctor_specialties TO 'rol_auditor';
GRANT SELECT ON medicita_ips.doctors TO 'rol_auditor';
GRANT SELECT ON medicita_ips.document_types TO 'rol_auditor';
GRANT SELECT ON medicita_ips.insurers TO 'rol_auditor';
GRANT SELECT ON medicita_ips.invoice_cancellations TO 'rol_auditor';
GRANT SELECT ON medicita_ips.invoice_items TO 'rol_auditor';
GRANT SELECT ON medicita_ips.invoices TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_exams TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_order_items TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_orders TO 'rol_auditor';
GRANT SELECT ON medicita_ips.lab_results TO 'rol_auditor';
GRANT SELECT ON medicita_ips.medications TO 'rol_auditor';
GRANT SELECT ON medicita_ips.monthly_production_summary TO 'rol_auditor';
GRANT SELECT ON medicita_ips.offices TO 'rol_auditor';
GRANT SELECT ON medicita_ips.patient_allergies TO 'rol_auditor';
GRANT SELECT ON medicita_ips.payment_methods TO 'rol_auditor';
GRANT SELECT ON medicita_ips.payments TO 'rol_auditor';
GRANT SELECT ON medicita_ips.plans TO 'rol_auditor';
GRANT SELECT ON medicita_ips.prescription_items TO 'rol_auditor';
GRANT SELECT ON medicita_ips.prescriptions TO 'rol_auditor';
GRANT SELECT ON medicita_ips.reminders TO 'rol_auditor';
GRANT SELECT ON medicita_ips.sites TO 'rol_auditor';
GRANT SELECT ON medicita_ips.specialties TO 'rol_auditor';
GRANT SELECT ON medicita_ips.surveys TO 'rol_auditor';
GRANT SELECT ON medicita_ips.system_users TO 'rol_auditor';
GRANT SELECT ON medicita_ips.tariffs TO 'rol_auditor';
GRANT SELECT ON medicita_ips.vital_signs TO 'rol_auditor';

-- ---- rol_admin_bd ----------------------------------------------------
-- Puede: todo sobre medicita_ips. No puede: nada fuera de medicita_ips.
GRANT ALL PRIVILEGES ON medicita_ips.* TO 'rol_admin_bd';

-- ---------------------------------------------------------------------
-- 3. Un usuario de prueba por rol, con el rol ACTIVO por defecto
--    (sin SET DEFAULT ROLE el usuario entra con CURRENT_ROLE() = NONE)
-- ---------------------------------------------------------------------
CREATE USER 'recepcion1_medicita'@'localhost' IDENTIFIED BY 'Practica_2026*';
CREATE USER 'medico1_medicita'@'localhost' IDENTIFIED BY 'Practica_2026*';
CREATE USER 'facturacion1_medicita'@'localhost' IDENTIFIED BY 'Practica_2026*';
CREATE USER 'auditor1_medicita'@'localhost' IDENTIFIED BY 'Practica_2026*';
CREATE USER 'admin1_medicita'@'localhost' IDENTIFIED BY 'Practica_2026*';

GRANT 'rol_recepcion' TO 'recepcion1_medicita'@'localhost';
GRANT 'rol_medico' TO 'medico1_medicita'@'localhost';
GRANT 'rol_facturacion' TO 'facturacion1_medicita'@'localhost';
GRANT 'rol_auditor' TO 'auditor1_medicita'@'localhost';
GRANT 'rol_admin_bd' TO 'admin1_medicita'@'localhost';

SET DEFAULT ROLE 'rol_recepcion' TO 'recepcion1_medicita'@'localhost';
SET DEFAULT ROLE 'rol_medico' TO 'medico1_medicita'@'localhost';
SET DEFAULT ROLE 'rol_facturacion' TO 'facturacion1_medicita'@'localhost';
SET DEFAULT ROLE 'rol_auditor' TO 'auditor1_medicita'@'localhost';
SET DEFAULT ROLE 'rol_admin_bd' TO 'admin1_medicita'@'localhost';

-- ---------------------------------------------------------------------
-- 4. SHOW GRANTS de cada usuario (con USING se ve lo que trae el rol)
-- ---------------------------------------------------------------------
SHOW GRANTS FOR 'recepcion1_medicita'@'localhost';
SHOW GRANTS FOR 'recepcion1_medicita'@'localhost' USING 'rol_recepcion';
SHOW GRANTS FOR 'medico1_medicita'@'localhost' USING 'rol_medico';
SHOW GRANTS FOR 'facturacion1_medicita'@'localhost' USING 'rol_facturacion';
SHOW GRANTS FOR 'auditor1_medicita'@'localhost' USING 'rol_auditor';
SHOW GRANTS FOR 'admin1_medicita'@'localhost' USING 'rol_admin_bd';



-- ---------------------------------------------------------------------
-- 5. Evidencia por rol (COMENTADA). Para repetirla, abre una SEGUNDA conexión
--    con el usuario de prueba (en la terminal de VS Code:
--      mysql -u recepcion1_medicita -p medicita_ips      ← contraseña Practica_2026*)
--    y ejecuta cada sentencia. Debajo de cada una está la salida real obtenida
--    en MySQL 8.0 (después de correr 01 a 08 en orden).
-- ---------------------------------------------------------------------
--
-- SHOW GRANTS sin USING (lo mismo para los 5 usuarios: solo se ve el rol):
--   GRANT USAGE ON *.* TO `recepcion1_medicita`@`localhost`
--   GRANT `rol_recepcion`@`%` TO `recepcion1_medicita`@`localhost`
-- Con USING 'rol_…' se ve el detalle: recepción 26 líneas, médico 29,
-- facturación 27, auditor 46 (patients por columnas) y admin 3
-- (GRANT ALL PRIVILEGES ON `medicita_ips`.*).
--
-- ========== ⚡ Conexión: recepcion1_medicita (rol_recepcion) ==========
--
-- ✅ PERMITIDO
-- SELECT CURRENT_ROLE();
--   +---------------------+
--   | CURRENT_ROLE()      |
--   +---------------------+
--   | `rol_recepcion`@`%` |
--   +---------------------+
--
-- ✅ PERMITIDO
-- SELECT id, first_name, last_name FROM patients WHERE id = 1;
--   +----+------------+----------------+
--   | id | first_name | last_name      |
--   +----+------------+----------------+
--   |  1 | Rosa Elena | Quintero Díaz |
--   +----+------------+----------------+
--
-- ✅ PERMITIDO
-- CALL sp_agendar_cita(17, 12, 1, 4, 1, '2026-12-03 10:00:00', 2, @c);
-- SELECT @c AS cita_nueva;
-- CALL sp_cancelar_cita(@c, 7, 2, '2026-11-29 18:00:00');
-- SELECT id, status, cancellation_reason_id FROM appointments WHERE id = @c;
--   +------------+
--   | cita_nueva |
--   +------------+
--   |        195 |
--   +------------+
--   +-----+-----------+------------------------+
--   | id  | status    | cancellation_reason_id |
--   +-----+-----------+------------------------+
--   | 195 | CANCELADA |                      7 |
--   +-----+-----------+------------------------+
--
-- ❌ DENEGADO
-- UPDATE appointments SET status = 'CONFIRMADA' WHERE id = 176;
--   ERROR 1142 (42000): UPDATE command denied to user 'recepcion1_medicita'@'localhost' for table 'appointments'
--
-- ❌ DENEGADO
-- SELECT * FROM attention_diagnoses LIMIT 1;
--   ERROR 1142 (42000): SELECT command denied to user 'recepcion1_medicita'@'localhost' for table 'attention_diagnoses'
--
-- ❌ DENEGADO
-- SELECT * FROM invoices LIMIT 1;
--   ERROR 1142 (42000): SELECT command denied to user 'recepcion1_medicita'@'localhost' for table 'invoices'
--
-- ❌ DENEGADO
-- CALL sp_facturar_atencion(122, '2026-11-27', @f);
--   ERROR 1370 (42000): execute command denied to user 'recepcion1_medicita'@'localhost' for routine 'medicita_ips.sp_facturar_atencion'
--
-- ========== ⚡ Conexión: medico1_medicita (rol_medico) ==========
--
-- ✅ PERMITIDO
-- SELECT id, start_at, status FROM appointments WHERE doctor_id = 4 AND DATE(start_at) = '2026-12-01';
--   +-----+---------------------+------------+
--   | id  | start_at            | status     |
--   +-----+---------------------+------------+
--   | 172 | 2026-12-01 07:00:00 | CONFIRMADA |
--   | 174 | 2026-12-01 08:00:00 | PROGRAMADA |
--   | 177 | 2026-12-01 10:20:00 | PROGRAMADA |
--   | 193 | 2026-12-01 11:00:00 | PROGRAMADA |
--   +-----+---------------------+------------+
--
-- ✅ PERMITIDO
-- INSERT INTO attention_diagnoses (attention_id, cie10_code_id, is_primary) VALUES (121, 5, NULL);
-- SELECT attention_id, cie10_code_id, is_primary FROM attention_diagnoses WHERE attention_id = 121;
--   +--------------+---------------+------------+
--   | attention_id | cie10_code_id | is_primary |
--   +--------------+---------------+------------+
--   |          121 |             4 |          1 |
--   |          121 |             5 |       NULL |
--   +--------------+---------------+------------+
--
-- ❌ DENEGADO
-- SELECT * FROM invoices LIMIT 1;
--   ERROR 1142 (42000): SELECT command denied to user 'medico1_medicita'@'localhost' for table 'invoices'
--
-- ❌ DENEGADO
-- DELETE FROM vital_signs WHERE attention_id = 121;
--   ERROR 1142 (42000): DELETE command denied to user 'medico1_medicita'@'localhost' for table 'vital_signs'
--
-- ========== ⚡ Conexión: facturacion1_medicita (rol_facturacion) ==========
--
-- ✅ PERMITIDO
-- CALL sp_facturar_atencion(122, '2026-11-27', @f);
-- SELECT id, invoice_number, total_amount, status FROM invoices WHERE id = @f;
--   +-----+----------------+--------------+-----------+
--   | id  | invoice_number | total_amount | status    |
--   +-----+----------------+--------------+-----------+
--   | 120 | FE-000120      |     48000.00 | PENDIENTE |
--   +-----+----------------+--------------+-----------+
--
-- ✅ PERMITIDO
-- INSERT INTO payments (invoice_id, payment_method_id, amount, paid_at, reference, received_by) VALUES (83, 1, 46000, '2026-11-29 10:00:00', 'REC-00083-1', 6);
-- SELECT id, status FROM invoices WHERE id = 83;
--   +----+--------+
--   | id | status |
--   +----+--------+
--   | 83 | PAGADA |
--   +----+--------+
--
-- ✅ PERMITIDO
-- CALL sp_anular_factura(87, '2026-11-29 11:00:00', 'Paciente registrado con otra aseguradora');
-- SELECT id, status FROM invoices WHERE id = 87;
--   +----+---------+
--   | id | status  |
--   +----+---------+
--   | 87 | ANULADA |
--   +----+---------+
--
-- ❌ DENEGADO
-- UPDATE invoices SET status = 'PAGADA' WHERE id = 91;
--   ERROR 1142 (42000): UPDATE command denied to user 'facturacion1_medicita'@'localhost' for table 'invoices'
--
-- ❌ DENEGADO
-- DELETE FROM invoices WHERE id = 91;
--   ERROR 1142 (42000): DELETE command denied to user 'facturacion1_medicita'@'localhost' for table 'invoices'
--
-- ❌ DENEGADO
-- SELECT * FROM prescriptions LIMIT 1;
--   ERROR 1142 (42000): SELECT command denied to user 'facturacion1_medicita'@'localhost' for table 'prescriptions'
--
-- ❌ DENEGADO
-- CALL sp_agendar_cita(17, 12, 3, 4, 3, '2026-12-03 10:00:00', 6, @c);
--   ERROR 1370 (42000): execute command denied to user 'facturacion1_medicita'@'localhost' for routine 'medicita_ips.sp_agendar_cita'
--
-- ========== ⚡ Conexión: auditor1_medicita (rol_auditor) ==========
--
-- ✅ PERMITIDO
-- SELECT id, first_name, last_name, birth_date FROM patients WHERE id = 1;
--   +----+------------+----------------+------------+
--   | id | first_name | last_name      | birth_date |
--   +----+------------+----------------+------------+
--   |  1 | Rosa Elena | Quintero Díaz | 1955-03-14 |
--   +----+------------+----------------+------------+
--
-- ✅ PERMITIDO
-- SELECT COUNT(*) AS facturas FROM invoices;
--   +----------+
--   | facturas |
--   +----------+
--   |      119 |
--   +----------+
--
-- ❌ DENEGADO
-- SELECT document_number FROM patients WHERE id = 1;
--   ERROR 1143 (42000): SELECT command denied to user 'auditor1_medicita'@'localhost' for column 'document_number' in table 'patients'
--
-- ❌ DENEGADO
-- SELECT * FROM patient_phones LIMIT 1;
--   ERROR 1142 (42000): SELECT command denied to user 'auditor1_medicita'@'localhost' for table 'patient_phones'
--
-- ❌ DENEGADO
-- UPDATE invoices SET status = 'PAGADA' WHERE id = 91;
--   ERROR 1142 (42000): UPDATE command denied to user 'auditor1_medicita'@'localhost' for table 'invoices'
--
-- ========== ⚡ Conexión: admin1_medicita (rol_admin_bd) ==========
--
-- ✅ PERMITIDO
-- SELECT COUNT(*) AS citas FROM appointments;
-- CREATE TABLE prueba_admin (id BIGINT AUTO_INCREMENT PRIMARY KEY);
-- DROP TABLE prueba_admin;
--   +-------+
--   | citas |
--   +-------+
--   |   194 |
--   +-------+
--
-- ❌ DENEGADO
-- SELECT user FROM mysql.user LIMIT 1;
--   ERROR 1142 (42000): SELECT command denied to user 'admin1_medicita'@'localhost' for table 'user'
--
-- ❌ DENEGADO
-- CREATE DATABASE otra_base;
--   ERROR 1044 (42000): Access denied for user 'admin1_medicita'@'localhost' to database 'otra_base'

-- ---------------------------------------------------------------------
-- 6. Script de limpieza (al terminar la práctica, con la conexión root).
--    Está comentado para que el evaluador alcance a probar los usuarios.
-- ---------------------------------------------------------------------
-- DROP USER IF EXISTS 'recepcion1_medicita'@'localhost', 'medico1_medicita'@'localhost',
--     'facturacion1_medicita'@'localhost', 'auditor1_medicita'@'localhost', 'admin1_medicita'@'localhost';
-- DROP ROLE IF EXISTS 'rol_recepcion', 'rol_medico', 'rol_facturacion', 'rol_auditor', 'rol_admin_bd';
-- SELECT user, host FROM mysql.user WHERE user LIKE '%medicita%' OR user LIKE 'rol_%';   -- debe salir vacío
