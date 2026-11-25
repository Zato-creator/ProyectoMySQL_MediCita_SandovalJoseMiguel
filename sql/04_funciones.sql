-- 04_funciones.sql - MediCita IPS - Jose Miguel Sandoval
-- =====================================================================
-- MediCita IPS · 04_funciones.sql
-- 5 funciones (de menor a mayor dificultad) con sus pruebas.
-- Estilo de clase: DROP … IF EXISTS, DELIMITER $$, p_ parámetros,
-- v_ variables y SIGNAL SQLSTATE '45000' con mensajes en español.
-- Fecha de corte del proyecto: 2026-11-30.
-- =====================================================================

USE medicita_ips;

-- ---------------------------------------------------------------------
-- F-1 · fn_edad(p_fecha_nacimiento, p_fecha_ref)
-- Edad en años cumplidos a una fecha.
-- DETERMINISTIC + NO SQL: solo calcula con lo que recibe, no lee tablas,
-- y con las mismas fechas siempre devuelve la misma edad.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_edad;

DELIMITER $$

CREATE FUNCTION fn_edad(p_fecha_nacimiento DATE, p_fecha_ref DATE)
RETURNS INT
DETERMINISTIC
NO SQL
BEGIN
    IF p_fecha_nacimiento IS NULL OR p_fecha_ref IS NULL THEN
        RETURN NULL;
    END IF;
    -- TIMESTAMPDIFF cuenta solo los años COMPLETOS (cumplidos)
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, p_fecha_ref);
END $$

DELIMITER ;

-- Pruebas F-1
SELECT fn_edad('1955-03-14', '2026-11-30') AS cumplio_71,
       fn_edad('1990-12-01', '2026-11-30') AS aun_no_cumple_36,
       fn_edad('1990-12-01', '2026-12-01') AS cumple_36_hoy;
-- Resultado esperado: 71 | 35 | 36

-- Usada dentro de una consulta: pacientes con su edad al corte
SELECT id, CONCAT(first_name, ' ', last_name) AS paciente, birth_date,
       fn_edad(birth_date, '2026-11-30') AS edad_al_corte
FROM patients
ORDER BY edad_al_corte DESC, id
LIMIT 5;

-- ---------------------------------------------------------------------
-- F-2 · fn_imc(p_peso_kg, p_talla_cm)
-- IMC = peso (kg) / talla (m)². Con 2 decimales. Talla 0 o nula → NULL.
-- DETERMINISTIC + NO SQL: es una fórmula, no lee tablas.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_imc;

DELIMITER $$

CREATE FUNCTION fn_imc(p_peso_kg DECIMAL(5,2), p_talla_cm DECIMAL(5,1))
RETURNS DECIMAL(5,2)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_talla_m DECIMAL(6,3);

    IF p_talla_cm IS NULL OR p_talla_cm = 0 OR p_peso_kg IS NULL THEN
        RETURN NULL;
    END IF;

    SET v_talla_m = p_talla_cm / 100;
    RETURN ROUND(p_peso_kg / (v_talla_m * v_talla_m), 2);
END $$

DELIMITER ;

-- Pruebas F-2
SELECT fn_imc(70, 175) AS imc_normal,
       fn_imc(98, 160) AS imc_obesidad,
       fn_imc(70, 0) AS talla_cero,
       fn_imc(70, NULL) AS talla_nula;
-- Resultado esperado: 22.86 | 38.28 | NULL | NULL

-- Usada sobre los signos vitales registrados
SELECT vs.attention_id, vs.weight_kg, vs.height_cm,
       fn_imc(vs.weight_kg, vs.height_cm) AS imc
FROM vital_signs AS vs
ORDER BY imc DESC
LIMIT 5;

-- ---------------------------------------------------------------------
-- F-3 · fn_tarifa_vigente(p_servicio, p_plan, p_fecha)
-- Precio del servicio para ese plan vigente en esa fecha.
-- Si no hay tarifa vigente lanza un error claro.
-- NOT DETERMINISTIC + READS SQL DATA: lee la tabla tariffs, y el mismo
-- (servicio, plan, fecha) puede dar otro precio si alguien cambia las tarifas.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_tarifa_vigente;

DELIMITER $$

CREATE FUNCTION fn_tarifa_vigente(p_servicio BIGINT, p_plan BIGINT, p_fecha DATE)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_precio DECIMAL(12,2) DEFAULT NULL;
    DECLARE v_mensaje VARCHAR(200);

    SELECT t.price INTO v_precio
    FROM tariffs AS t
    WHERE t.cups_service_id = p_servicio
      AND t.plan_id = p_plan
      AND p_fecha BETWEEN t.valid_from AND t.valid_to
    ORDER BY t.valid_from DESC
    LIMIT 1;

    IF v_precio IS NULL THEN
        SET v_mensaje = CONCAT('No hay tarifa vigente para el servicio ', p_servicio,
                               ' en el plan ', p_plan, ' el día ', p_fecha);
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_mensaje;
    END IF;

    RETURN v_precio;
END $$

DELIMITER ;

-- Pruebas F-3: la consulta de primera vez de medicina general (servicio 1)
-- en plan CONTRIBUTIVO (1) tiene dos vigencias: hasta el 31-oct y desde el 1-nov
SELECT fn_tarifa_vigente(1, 1, '2026-10-15') AS tarifa_15_oct,
       fn_tarifa_vigente(1, 1, '2026-11-15') AS tarifa_15_nov,
       fn_tarifa_vigente(1, 4, '2026-11-30') AS particular_al_corte;
-- Resultado esperado: 42000.00 | 46000.00 | 65000.00

-- ⚠️ ESPERADO: ERROR 1644 (45000): No hay tarifa vigente para el servicio 1 en el plan 1 el día 2025-06-01
SELECT fn_tarifa_vigente(1, 1, '2025-06-01') AS tarifa_2025;

-- ---------------------------------------------------------------------
-- F-4 · fn_saldo_factura(p_factura)
-- Total de la factura menos la suma de sus abonos. Anulada → saldo 0.
-- NOT DETERMINISTIC + READS SQL DATA: lee invoices y payments, y el saldo
-- cambia cada vez que entra un abono.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_saldo_factura;

DELIMITER $$

CREATE FUNCTION fn_saldo_factura(p_factura BIGINT)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT NULL;
    DECLARE v_estado VARCHAR(20);
    DECLARE v_abonado DECIMAL(12,2);

    SELECT i.total_amount, i.status INTO v_total, v_estado
    FROM invoices AS i
    WHERE i.id = p_factura;

    IF v_total IS NULL THEN
        RETURN NULL;          -- la factura no existe
    END IF;

    IF v_estado = 'ANULADA' THEN
        RETURN 0;
    END IF;

    SELECT IFNULL(SUM(p.amount), 0) INTO v_abonado
    FROM payments AS p
    WHERE p.invoice_id = p_factura;

    RETURN v_total - v_abonado;
END $$

DELIMITER ;

-- Pruebas F-4
SELECT fn_saldo_factura(2) AS parcial,
       fn_saldo_factura(4) AS pagada,
       fn_saldo_factura(5) AS anulada,
       fn_saldo_factura(999) AS no_existe;
-- Resultado esperado: 46200.00 | 0.00 | 0.00 | NULL

-- Usada en una consulta: las 5 facturas con más saldo pendiente
SELECT i.invoice_number, i.status, i.total_amount, fn_saldo_factura(i.id) AS saldo
FROM invoices AS i
ORDER BY saldo DESC, i.id
LIMIT 5;

-- ---------------------------------------------------------------------
-- F-5 · fn_medico_disponible(p_medico, p_inicio, p_duracion_min)
-- 1 si el médico puede atender en ese intervalo, 0 si no. Debe cumplir:
--   a) el intervalo cae COMPLETO dentro de su horario de ese día de la semana;
--   b) no tiene una novedad (vacaciones, incapacidad…) que cubra esa fecha;
--   c) no se cruza con otra cita suya que no esté CANCELADA.
-- NOT DETERMINISTIC + READS SQL DATA: lee horarios, novedades y citas, y la
-- respuesta cambia cada vez que se agenda o se cancela una cita.
-- ---------------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_medico_disponible;

DELIMITER $$

CREATE FUNCTION fn_medico_disponible(p_medico BIGINT, p_inicio DATETIME, p_duracion_min INT)
RETURNS TINYINT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_fin DATETIME;
    DECLARE v_dia VARCHAR(10);
    DECLARE v_activo BOOLEAN DEFAULT NULL;
    DECLARE v_en_horario INT;
    DECLARE v_novedades INT;
    DECLARE v_cruces INT;

    SET v_fin = DATE_ADD(p_inicio, INTERVAL p_duracion_min MINUTE);
    -- WEEKDAY(): 0 = lunes … 6 = domingo
    SET v_dia = ELT(WEEKDAY(p_inicio) + 1, 'LUNES', 'MARTES', 'MIERCOLES', 'JUEVES',
                    'VIERNES', 'SABADO', 'DOMINGO');

    -- 0. El médico existe y está activo
    SELECT d.is_active INTO v_activo FROM doctors AS d WHERE d.id = p_medico;
    IF v_activo IS NULL OR v_activo = FALSE THEN
        RETURN 0;
    END IF;

    -- a) Dentro de su horario (y sin pasar a otro día)
    SELECT COUNT(*) INTO v_en_horario
    FROM doctor_schedules AS s
    WHERE s.doctor_id = p_medico
      AND s.day_of_week = v_dia
      AND s.start_time <= TIME(p_inicio)
      AND s.end_time >= TIME(v_fin)
      AND DATE(v_fin) = DATE(p_inicio);
    IF v_en_horario = 0 THEN
        RETURN 0;
    END IF;

    -- b) Sin novedad ese día
    SELECT COUNT(*) INTO v_novedades
    FROM doctor_absences AS da
    WHERE da.doctor_id = p_medico
      AND DATE(p_inicio) BETWEEN da.start_date AND da.end_date;
    IF v_novedades > 0 THEN
        RETURN 0;
    END IF;

    -- c) Sin cruce con otra cita no cancelada.
    --    Dos intervalos se cruzan si cada uno empieza antes de que el otro termine.
    SELECT COUNT(*) INTO v_cruces
    FROM appointments AS a
    JOIN appointment_types AS t ON t.id = a.appointment_type_id
    WHERE a.doctor_id = p_medico
      AND a.status <> 'CANCELADA'
      AND a.start_at < v_fin
      AND DATE_ADD(a.start_at, INTERVAL t.duration_minutes MINUTE) > p_inicio;
    IF v_cruces > 0 THEN
        RETURN 0;
    END IF;

    RETURN 1;
END $$

DELIMITER ;

-- Pruebas F-5 (la doctora Rojas, id 4, atiende los martes de 07:00 a 12:00 en el
-- consultorio 202 de Cañaveral; el doctor Arenas, id 5, está de vacaciones del 7 al 18 de diciembre)
SELECT fn_medico_disponible(4, '2026-12-01 11:00:00', 20) AS libre,
       fn_medico_disponible(4, '2026-12-01 07:00:00', 20) AS cruce_con_cita,
       fn_medico_disponible(4, '2026-12-01 11:50:00', 20) AS se_pasa_del_horario,
       fn_medico_disponible(4, '2026-12-02 08:00:00', 20) AS dia_sin_horario,
       fn_medico_disponible(5, '2026-12-07 14:00:00', 20) AS en_vacaciones,
       fn_medico_disponible(11, '2026-12-01 08:00:00', 20) AS medico_inactivo;
-- Resultado esperado: 1 | 0 | 0 | 0 | 0 | 0

-- Una cita CANCELADA no ocupa el espacio: la doctora Ortega (12) tenía una a las 15:00
-- del 1-dic, pero se canceló, así que ese horario vuelve a estar libre
SELECT fn_medico_disponible(12, '2026-12-01 15:00:00', 20) AS libre_tras_cancelacion;
-- Resultado esperado: 1

-- Revisión: deben aparecer las 5 funciones
SHOW FUNCTION STATUS WHERE Db = 'medicita_ips';
