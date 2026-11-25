-- Comandos para tomar las capturas del README (sección 9).
-- Se pueden ejecutar las veces que quieras: no dañan los datos.
USE medicita_ips;

-- 1) PROCEDIMIENTO · capturas/procedimiento.png
CALL sp_reporte_produccion('2026-11-01', '2026-11-30');

-- 2) TRIGGER T-5 · capturas/trigger.png
-- Laura (paciente 3) es alérgica al ibuprofeno. Tomamos la fórmula de prueba de su atención 121.
SELECT MAX(id) INTO @formula FROM prescriptions WHERE attention_id = 121;
-- Debe salir: ERROR 1644 ... alérgico al principio activo Ibuprofeno
INSERT INTO prescription_items (prescription_id, medication_id, dose, frequency, duration_days)
VALUES (@formula, 1, '1 tableta', 'Cada 8 horas', 5);
-- Lo que sí quedó formulado (Dolex, acetaminofén):
SELECT pi.prescription_id, m.commercial_name, ai.name AS principio_activo, pi.dose, pi.frequency
FROM prescription_items pi
JOIN medications m ON m.id = pi.medication_id
JOIN active_ingredients ai ON ai.id = m.active_ingredient_id
WHERE pi.prescription_id = @formula;

-- 3) EVENTO E-1 · capturas/evento.png
-- Citas que el evento pasó a NO_ASISTIO y su historial.
SELECT h.appointment_id AS cita, h.previous_status AS antes, h.new_status AS despues,
       h.changed_at AS cuando, u.full_name AS responsable
FROM appointment_status_history h
JOIN system_users u ON u.id = h.changed_by
WHERE h.new_status = 'NO_ASISTIO'
ORDER BY h.id DESC
LIMIT 5;

-- 4) CONSULTA 9 · capturas/consulta_09.png
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

-- 5) CONSULTA 19 · capturas/consulta_19.png
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

-- 6) CONSULTA 30 · capturas/consulta_30.png
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
