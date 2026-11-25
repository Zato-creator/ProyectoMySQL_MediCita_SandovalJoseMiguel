-- 03_dql.sql - MediCita IPS - Jose Miguel Sandoval
-- =====================================================================
-- MediCita IPS · 03_dql.sql
-- Fase 4 · 30 consultas
-- Fecha de corte del proyecto: 2026-11-30
--  1–8   una tabla
--  9–15  JOIN
-- 16–20  agregación y LEFT JOIN
-- 21–30  subconsultas (y CTE / funciones de ventana en la 30)
-- Los montos van con 2 decimales.
-- =====================================================================

USE medicita_ips;


-- =====================================================================
-- UNA TABLA (1–8)
-- =====================================================================

-- Q1. Negocio: pacientes nacidos antes de 1960 (población mayor), del mayor al menor.
--     Técnica: WHERE con fecha, CONCAT para el nombre y ORDER BY fecha ascendente
--     (la fecha más antigua es la persona de más edad).
--     El documento se muestra con el id del tipo y el número porque la consulta es de una sola tabla.
SELECT
    CONCAT(document_type_id, '-', document_number) AS documento,
    CONCAT(first_name, ' ', last_name)             AS nombre_completo,
    birth_date                                     AS fecha_nacimiento
FROM patients
WHERE birth_date < '1960-01-01'
ORDER BY birth_date ASC;


-- Q2. Negocio: directorio de médicos activos con su registro y correo, por apellido.
--     Técnica: filtro por columna booleana y ORDER BY por apellido y nombre.
SELECT
    last_name           AS apellido,
    first_name          AS nombre,
    medical_license     AS registro_medico,
    institutional_email AS correo
FROM doctors
WHERE is_active = TRUE
ORDER BY last_name, first_name;


-- Q3. Negocio: citas que empiezan entre el 1 y el 7 de diciembre de 2026, incluido todo el 7.
--     Técnica: rango semiabierto [2026-12-01, 2026-12-08) para no perder las horas del día 7.
SELECT
    id          AS cita,
    start_at    AS inicio,
    patient_id  AS paciente,
    doctor_id   AS medico,
    status      AS estado
FROM appointments
WHERE start_at >= '2026-12-01'
  AND start_at <  '2026-12-08'
ORDER BY start_at;


-- Q4. Negocio: exámenes de laboratorio que se miden en mg/dL, con su rango de referencia.
--     Técnica: WHERE por igualdad de texto.
SELECT
    code          AS codigo,
    name          AS examen,
    unit          AS unidad,
    reference_min AS minimo,
    reference_max AS maximo
FROM lab_exams
WHERE unit = 'mg/dL'
ORDER BY name;


-- Q5. Negocio: cuántas citas hay en cada estado, de la más frecuente a la menos frecuente.
--     Técnica: GROUP BY con COUNT y ORDER BY del conteo.
SELECT
    status   AS estado,
    COUNT(*) AS cantidad
FROM appointments
GROUP BY status
ORDER BY cantidad DESC;


-- Q6. Negocio: facturas emitidas en noviembre de 2026 por más de 150.000, de la más alta a la más baja.
--     Técnica: rango de fechas del mes y filtro de monto.
SELECT
    invoice_number AS factura,
    issued_at      AS emitida,
    total_amount   AS total,
    status         AS estado
FROM invoices
WHERE issued_at >= '2026-11-01'
  AND issued_at <  '2026-12-01'
  AND total_amount > 150000
ORDER BY total_amount DESC;


-- Q7. Negocio: pacientes sin correo registrado (para pedírselo en la próxima cita).
--     Técnica: IS NULL; también se cubre el texto vacío.
SELECT
    id                                 AS paciente,
    CONCAT(first_name, ' ', last_name) AS nombre_completo,
    email
FROM patients
WHERE email IS NULL OR email = ''
ORDER BY last_name, first_name;


-- Q8. Negocio: los 5 servicios con la tarifa vigente al corte más alta para el plan PARTICULAR.
--     Técnica: una sola tabla (tariffs); vigencia al corte con BETWEEN, ORDER BY y LIMIT.
--     El plan PARTICULAR se busca por nombre con una subconsulta escalar para no escribir su id a mano.
SELECT
    cups_service_id AS servicio,
    price           AS tarifa,
    valid_from      AS vigente_desde,
    valid_to        AS vigente_hasta
FROM tariffs
WHERE plan_id = (SELECT id FROM plans WHERE name = 'PARTICULAR')
  AND '2026-11-30' BETWEEN valid_from AND valid_to
ORDER BY price DESC
LIMIT 5;


-- =====================================================================
-- JOINs (9–15)
-- =====================================================================

-- Q9. Negocio: la agenda del martes 1 de diciembre de 2026 (sin las citas canceladas).
--     Técnica: INNER JOIN de la cita con paciente, médico, especialidad, consultorio y sede.
SELECT
    TIME(a.start_at)                     AS hora,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    s.name                               AS especialidad,
    o.code                               AS consultorio,
    si.name                              AS sede
FROM appointments a
JOIN patients    p  ON p.id  = a.patient_id
JOIN doctors     d  ON d.id  = a.doctor_id
JOIN specialties s  ON s.id  = a.specialty_id
JOIN offices     o  ON o.id  = a.office_id
JOIN sites       si ON si.id = o.site_id
WHERE a.start_at >= '2026-12-01'
  AND a.start_at <  '2026-12-02'
  AND a.status <> 'CANCELADA'
ORDER BY a.start_at;


-- Q10. Negocio: cada paciente con su afiliación vigente al corte. Los particulares no salen.
--      Técnica: INNER JOIN (deja fuera a quien no tiene afiliación) y vigencia con fechas;
--      end_date NULL significa afiliación abierta.
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    i.name                                 AS aseguradora,
    pl.name                                AS plan,
    af.start_date                          AS desde,
    af.end_date                            AS hasta
FROM patients p
JOIN affiliations af ON af.patient_id = p.id
JOIN insurers     i  ON i.id  = af.insurer_id
JOIN plans        pl ON pl.id = af.plan_id
WHERE af.start_date <= '2026-11-30'
  AND (af.end_date IS NULL OR af.end_date >= '2026-11-30')
ORDER BY p.last_name, p.first_name;


-- Q11. Negocio: qué puede atender cada médico y dónde; una fila por médico–especialidad–sede.
--      Técnica: JOIN de las dos tablas puente. Al unirlas por el médico se reconstruyen
--      las combinaciones que la 4FN separó.
SELECT
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    sp.name                                AS especialidad,
    si.name                                AS sede
FROM doctors d
JOIN doctor_specialties ds ON ds.doctor_id = d.id
JOIN specialties        sp ON sp.id = ds.specialty_id
JOIN doctor_sites       dsi ON dsi.doctor_id = d.id
JOIN sites              si ON si.id = dsi.site_id
ORDER BY d.last_name, sp.name, si.name;


-- Q12. Negocio: diagnóstico principal de cada atención de noviembre de 2026.
--      Técnica: JOIN atención → cita → paciente/médico y atención → diagnóstico → CIE-10,
--      filtrando is_primary.
SELECT
    DATE(at.started_at)                    AS fecha,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    c.code                                 AS cie10,
    c.name                                 AS diagnostico
FROM attentions at
JOIN appointments        a  ON a.id = at.appointment_id
JOIN patients            p  ON p.id = a.patient_id
JOIN doctors             d  ON d.id = a.doctor_id
JOIN attention_diagnoses ad ON ad.attention_id = at.id AND ad.is_primary = TRUE
JOIN cie10_codes         c  ON c.id = ad.cie10_code_id
WHERE at.started_at >= '2026-11-01'
  AND at.started_at <  '2026-12-01'
ORDER BY at.started_at;


-- Q13. Negocio: detalle de las fórmulas emitidas, con el principio activo de cada medicamento.
--      Técnica: JOIN de la fórmula con sus renglones, el medicamento y su principio activo,
--      y con la atención para llegar al paciente y al médico.
SELECT
    DATE(pr.issued_at)                     AS fecha,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    m.commercial_name                      AS medicamento,
    ai.name                                AS principio_activo,
    pi.dose                                AS dosis,
    pi.frequency                           AS frecuencia,
    pi.duration_days                       AS dias
FROM prescriptions pr
JOIN prescription_items pi ON pi.prescription_id = pr.id
JOIN medications        m  ON m.id  = pi.medication_id
JOIN active_ingredients ai ON ai.id = m.active_ingredient_id
JOIN attentions         at ON at.id = pr.attention_id
JOIN appointments       a  ON a.id  = at.appointment_id
JOIN patients           p  ON p.id  = a.patient_id
JOIN doctors            d  ON d.id  = a.doctor_id
ORDER BY pr.issued_at, paciente;


-- Q14. Negocio: alertas clínicas; resultados de laboratorio por fuera del rango de referencia.
--      Técnica: JOIN resultado → renglón de la orden → examen, y NOT BETWEEN contra el rango.
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    e.name                                 AS examen,
    r.result_value                         AS valor,
    e.unit                                 AS unidad,
    e.reference_min                        AS minimo,
    e.reference_max                        AS maximo
FROM lab_results r
JOIN lab_order_items li ON li.id = r.lab_order_item_id
JOIN lab_exams       e  ON e.id  = li.lab_exam_id
JOIN lab_orders      lo ON lo.id = li.lab_order_id
JOIN attentions      at ON at.id = lo.attention_id
JOIN appointments    a  ON a.id  = at.appointment_id
JOIN patients        p  ON p.id  = a.patient_id
WHERE r.result_value NOT BETWEEN e.reference_min AND e.reference_max
ORDER BY paciente, e.name;


-- Q15. Negocio: citas canceladas con su motivo, quién las canceló y cuándo, según el historial.
--      Técnica: JOIN con el historial filtrado al cambio hacia CANCELADA,
--      con el catálogo de motivos y con el usuario responsable.
SELECT
    h.appointment_id                       AS cita,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    cr.name                                AS motivo,
    u.full_name                            AS cancelada_por,
    h.changed_at                           AS cuando
FROM appointment_status_history h
JOIN appointments         a  ON a.id  = h.appointment_id
JOIN patients             p  ON p.id  = a.patient_id
JOIN cancellation_reasons cr ON cr.id = h.cancellation_reason_id
JOIN system_users         u  ON u.id  = h.changed_by
WHERE h.new_status = 'CANCELADA'
ORDER BY h.changed_at;


-- =====================================================================
-- AGREGACIÓN Y LEFT JOIN (16–20)
-- =====================================================================

-- Q16. Negocio: volumen de atenciones por especialidad y mes; solo combinaciones con 3 o más.
--      Técnica: GROUP BY de dos columnas y HAVING sobre el conteo.
SELECT
    sp.name                            AS especialidad,
    DATE_FORMAT(at.started_at, '%Y-%m') AS mes,
    COUNT(*)                           AS atenciones
FROM attentions at
JOIN appointments a  ON a.id  = at.appointment_id
JOIN specialties  sp ON sp.id = a.specialty_id
GROUP BY sp.name, DATE_FORMAT(at.started_at, '%Y-%m')
HAVING COUNT(*) >= 3
ORDER BY mes, atenciones DESC;


-- Q17. Negocio: médicos activos sin ninguna cita en diciembre de 2026.
--      Técnica: anti-join con LEFT JOIN; la condición del mes va en el ON
--      para no convertirlo en INNER JOIN, y luego WHERE a.id IS NULL.
SELECT
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    d.medical_license                      AS registro_medico
FROM doctors d
LEFT JOIN appointments a
       ON a.doctor_id = d.id
      AND a.start_at >= '2026-12-01'
      AND a.start_at <  '2027-01-01'
WHERE d.is_active = TRUE
  AND a.id IS NULL
ORDER BY d.last_name;


-- Q18. Negocio: porcentaje de inasistencia por sede (NO_ASISTIO sobre todas las citas
--      que empezaron antes del corte, incluidas las canceladas), de la peor sede a la mejor.
--      Técnica: LEFT JOIN sede → consultorio → cita, SUM de una condición y NULLIF para no dividir por 0.
SELECT
    si.name AS sede,
    COUNT(a.id)                              AS citas_antes_del_corte,
    SUM(a.status = 'NO_ASISTIO')             AS inasistencias,
    ROUND(100 * SUM(a.status = 'NO_ASISTIO') / NULLIF(COUNT(a.id), 0), 2) AS porcentaje_inasistencia
FROM sites si
LEFT JOIN offices o ON o.site_id = si.id
LEFT JOIN appointments a
       ON a.office_id = o.id
      AND a.start_at < '2026-11-30'
GROUP BY si.id, si.name
ORDER BY porcentaje_inasistencia DESC;


-- Q19. Negocio: cartera por aseguradora: total facturado (sin anuladas), total abonado y saldo.
--      Técnica: se suman los abonos por factura en una tabla derivada ANTES del JOIN,
--      así cada factura aparece una sola vez y su total no se duplica por tener varios abonos.
SELECT
    i.name                                          AS aseguradora,
    ROUND(COALESCE(SUM(f.total_amount), 0), 2)      AS total_facturado,
    ROUND(COALESCE(SUM(f.abonado), 0), 2)           AS total_abonado,
    ROUND(COALESCE(SUM(f.total_amount - f.abonado), 0), 2) AS saldo
FROM insurers i
LEFT JOIN (
    SELECT inv.id, af.insurer_id, inv.total_amount,
           COALESCE(pg.abonado, 0) AS abonado
    FROM invoices inv
    JOIN affiliations af ON af.id = inv.affiliation_id
    LEFT JOIN (SELECT invoice_id, SUM(amount) AS abonado
               FROM payments
               GROUP BY invoice_id) pg ON pg.invoice_id = inv.id
    WHERE inv.status <> 'ANULADA'
) f ON f.insurer_id = i.id
GROUP BY i.id, i.name
ORDER BY saldo DESC;


-- Q20. Negocio: satisfacción promedio por médico, solo con 2 o más encuestas, del mejor al peor.
--      Técnica: AVG y COUNT agrupados, con HAVING.
SELECT
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    ROUND(AVG(sv.score), 2)                AS promedio,
    COUNT(*)                               AS encuestas
FROM surveys sv
JOIN appointments a ON a.id = sv.appointment_id
JOIN doctors      d ON d.id = a.doctor_id
GROUP BY d.id, d.first_name, d.last_name
HAVING COUNT(*) >= 2
ORDER BY promedio DESC, encuestas DESC;


-- =====================================================================
-- SUBCONSULTAS (21–30)
-- =====================================================================

-- Q21. Negocio: pacientes que piden más citas que el promedio por paciente.
--      Técnica: subconsulta en el HAVING que calcula el promedio de citas por paciente
--      (a su vez, a partir de una tabla derivada con el conteo de cada paciente).
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    COUNT(a.id)                            AS citas
FROM patients p
JOIN appointments a ON a.patient_id = p.id
GROUP BY p.id, p.first_name, p.last_name
HAVING COUNT(a.id) > (
    SELECT AVG(t.n)
    FROM (SELECT patient_id, COUNT(*) AS n
          FROM appointments
          GROUP BY patient_id) t
)
ORDER BY citas DESC;


-- Q22. Negocio: médicos que han atendido al paciente con más atenciones de la IPS (con empates).
--      Técnica: subconsulta con IN que busca al o los pacientes cuyo número de atenciones
--      es igual al máximo (subconsulta anidada con MAX).
SELECT DISTINCT
    CONCAT(d.first_name, ' ', d.last_name) AS medico,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente
FROM attentions at
JOIN appointments a ON a.id = at.appointment_id
JOIN doctors      d ON d.id = a.doctor_id
JOIN patients     p ON p.id = a.patient_id
WHERE a.patient_id IN (
    SELECT a2.patient_id
    FROM attentions at2
    JOIN appointments a2 ON a2.id = at2.appointment_id
    GROUP BY a2.patient_id
    HAVING COUNT(*) = (
        SELECT MAX(n)
        FROM (SELECT a3.patient_id, COUNT(*) AS n
              FROM attentions at3
              JOIN appointments a3 ON a3.id = at3.appointment_id
              GROUP BY a3.patient_id) t
    )
)
ORDER BY paciente, medico;


-- Q23. Negocio: consultorios que nunca han tenido una cita.
--      Técnica: NOT EXISTS correlacionado.
SELECT
    si.name AS sede,
    o.code  AS consultorio
FROM offices o
JOIN sites si ON si.id = o.site_id
WHERE NOT EXISTS (
    SELECT 1
    FROM appointments a
    WHERE a.office_id = o.id
)
ORDER BY si.name, o.code;


-- Q24. Negocio: pacientes alérgicos que sí tienen fórmulas, para revisar que ninguna choque con su alergia.
--      Técnica: dos EXISTS correlacionados (tiene alergia y tiene fórmula).
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    (SELECT GROUP_CONCAT(ai.name ORDER BY ai.name SEPARATOR ', ')
     FROM patient_allergies pa
     JOIN active_ingredients ai ON ai.id = pa.active_ingredient_id
     WHERE pa.patient_id = p.id)            AS alergias
FROM patients p
WHERE EXISTS (SELECT 1 FROM patient_allergies pa WHERE pa.patient_id = p.id)
  AND EXISTS (SELECT 1
              FROM prescriptions pr
              JOIN attentions   at ON at.id = pr.attention_id
              JOIN appointments a  ON a.id  = at.appointment_id
              WHERE a.patient_id = p.id)
ORDER BY paciente;


-- Q25. Negocio: por cada especialidad, el médico con más atenciones (si hay empate, salen todos).
--      Técnica: tabla derivada con el conteo por especialidad y médico, y subconsulta correlacionada
--      que obtiene el máximo de esa misma especialidad.
SELECT
    t.especialidad,
    t.medico,
    t.atenciones
FROM (
    SELECT sp.id AS specialty_id, sp.name AS especialidad,
           CONCAT(d.first_name, ' ', d.last_name) AS medico,
           COUNT(*) AS atenciones
    FROM attentions at
    JOIN appointments a  ON a.id  = at.appointment_id
    JOIN specialties  sp ON sp.id = a.specialty_id
    JOIN doctors      d  ON d.id  = a.doctor_id
    GROUP BY sp.id, sp.name, d.id, d.first_name, d.last_name
) t
WHERE t.atenciones = (
    SELECT MAX(x.n)
    FROM (SELECT a2.specialty_id, a2.doctor_id, COUNT(*) AS n
          FROM attentions at2
          JOIN appointments a2 ON a2.id = at2.appointment_id
          GROUP BY a2.specialty_id, a2.doctor_id) x
    WHERE x.specialty_id = t.specialty_id
)
ORDER BY t.especialidad, t.medico;


-- Q26. Negocio: facturas cuyo total supera el promedio de las facturas de su misma aseguradora.
--      Técnica: subconsulta correlacionada en el WHERE (el promedio se calcula por aseguradora
--      de la fila externa). No cuentan las anuladas ni las de particulares (sin aseguradora).
SELECT
    i.name             AS aseguradora,
    inv.invoice_number AS factura,
    inv.total_amount   AS total
FROM invoices inv
JOIN affiliations af ON af.id = inv.affiliation_id
JOIN insurers     i  ON i.id  = af.insurer_id
WHERE inv.status <> 'ANULADA'
  AND inv.total_amount > (
      SELECT AVG(inv2.total_amount)
      FROM invoices inv2
      JOIN affiliations af2 ON af2.id = inv2.affiliation_id
      WHERE af2.insurer_id = af.insurer_id
        AND inv2.status <> 'ANULADA'
  )
ORDER BY i.name, inv.total_amount DESC;


-- Q27. Negocio: producción por sede en noviembre de 2026 y su participación sobre el total de la IPS.
--      Técnica: subconsulta en el FROM con el total por sede y subconsulta escalar con el total general.
SELECT
    t.sede,
    ROUND(t.facturado, 2) AS total_facturado,
    ROUND(100 * t.facturado / (
        SELECT SUM(inv.total_amount)
        FROM invoices inv
        WHERE inv.status <> 'ANULADA'
          AND inv.issued_at >= '2026-11-01' AND inv.issued_at < '2026-12-01'
    ), 2) AS participacion_pct
FROM (
    SELECT si.name AS sede, SUM(inv.total_amount) AS facturado
    FROM invoices inv
    JOIN attentions   at ON at.id = inv.attention_id
    JOIN appointments a  ON a.id  = at.appointment_id
    JOIN offices      o  ON o.id  = a.office_id
    JOIN sites        si ON si.id = o.site_id
    WHERE inv.status <> 'ANULADA'
      AND inv.issued_at >= '2026-11-01' AND inv.issued_at < '2026-12-01'
    GROUP BY si.id, si.name
) t
ORDER BY total_facturado DESC;


-- Q28. Negocio: la última cita de cada paciente hasta el corte (sin citas futuras)
--      y cuántos días han pasado desde ella.
--      Técnica: subconsulta correlacionada con MAX en el WHERE y DATEDIFF contra el corte.
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    a.start_at                             AS ultima_cita,
    a.status                               AS estado,
    DATEDIFF('2026-11-30', a.start_at)     AS dias_hasta_el_corte
FROM appointments a
JOIN patients p ON p.id = a.patient_id
WHERE a.start_at = (
    SELECT MAX(a2.start_at)
    FROM appointments a2
    WHERE a2.patient_id = a.patient_id
      AND a2.start_at < '2026-12-01'
)
ORDER BY dias_hasta_el_corte DESC;


-- Q29. Negocio: seguimiento de hipertensos (I10) cuya última presión sistólica es 140 o más.
--      Técnica: IN para los pacientes con I10 y subconsulta correlacionada que trae
--      la toma de signos vitales más reciente del paciente.
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    vs.measured_at                         AS ultima_toma,
    vs.systolic_bp                         AS sistolica,
    vs.diastolic_bp                        AS diastolica
FROM vital_signs vs
JOIN attentions   at ON at.id = vs.attention_id
JOIN appointments a  ON a.id  = at.appointment_id
JOIN patients     p  ON p.id  = a.patient_id
WHERE a.patient_id IN (
        SELECT a2.patient_id
        FROM attention_diagnoses ad
        JOIN cie10_codes  c  ON c.id  = ad.cie10_code_id
        JOIN attentions   t2 ON t2.id = ad.attention_id
        JOIN appointments a2 ON a2.id = t2.appointment_id
        WHERE c.code = 'I10'
  )
  AND vs.measured_at = (
        SELECT MAX(vs3.measured_at)
        FROM vital_signs vs3
        JOIN attentions   t3 ON t3.id = vs3.attention_id
        JOIN appointments a3 ON a3.id = t3.appointment_id
        WHERE a3.patient_id = a.patient_id
  )
  AND vs.systolic_bp >= 140
ORDER BY vs.systolic_bp DESC;


-- Q30. Negocio: los 3 diagnósticos más frecuentes de cada sede, con su posición;
--      si empatan, va primero el de menor código CIE-10.
--      Técnica: CTE con el conteo por sede y diagnóstico, y ROW_NUMBER() OVER (PARTITION BY sede)
--      ordenando por frecuencia y luego por código. Se usa ROW_NUMBER y no RANK porque el
--      desempate por código ya define una posición única y así salen exactamente 3 por sede.
WITH conteo AS (
    SELECT si.name AS sede, c.code, c.name AS diagnostico, COUNT(*) AS veces
    FROM attention_diagnoses ad
    JOIN cie10_codes  c  ON c.id  = ad.cie10_code_id
    JOIN attentions   at ON at.id = ad.attention_id
    JOIN appointments a  ON a.id  = at.appointment_id
    JOIN offices      o  ON o.id  = a.office_id
    JOIN sites        si ON si.id = o.site_id
    GROUP BY si.name, c.code, c.name
),
ranking AS (
    SELECT sede, code, diagnostico, veces,
           ROW_NUMBER() OVER (PARTITION BY sede ORDER BY veces DESC, code ASC) AS posicion
    FROM conteo
)
SELECT sede, posicion, code AS cie10, diagnostico, veces
FROM ranking
WHERE posicion <= 3
ORDER BY sede, posicion;
