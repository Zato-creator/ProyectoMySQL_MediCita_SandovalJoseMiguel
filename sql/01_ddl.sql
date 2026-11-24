-- =====================================================================
-- MediCita IPS · 01_ddl.sql
-- Modelo físico: 46 tablas en 13 módulos
-- Convenciones: inglés snake_case, id BIGINT AUTO_INCREMENT PRIMARY KEY,
-- restricciones en línea, FK sin nombre, ENUM en español y MAYÚSCULAS,
-- dinero en DECIMAL(12,2), sin CHARACTER SET ni COLLATE.
-- =====================================================================

DROP DATABASE IF EXISTS medicita_ips;
CREATE DATABASE medicita_ips;
USE medicita_ips;


-- ---------------------------------------------------------------------
-- Módulo 1 · Organización
-- ---------------------------------------------------------------------

-- Ciudades (de las sedes y de los pacientes)
CREATE TABLE cities (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    department VARCHAR(80) NOT NULL,
    UNIQUE (name, department)
);

-- Las 4 sedes de la IPS
CREATE TABLE sites (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(60) NOT NULL UNIQUE,
    city_id BIGINT NOT NULL,
    address VARCHAR(150) NOT NULL,
    phone VARCHAR(20) NULL,
    FOREIGN KEY (city_id) REFERENCES cities(id)
);

-- Consultorios de cada sede (ej. 101)
CREATE TABLE offices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    site_id BIGINT NOT NULL,
    code VARCHAR(10) NOT NULL,
    floor TINYINT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (site_id, code),
    FOREIGN KEY (site_id) REFERENCES sites(id)
);

-- ---------------------------------------------------------------------
-- Módulo 2 · Médicos
-- ---------------------------------------------------------------------

-- Medicina general, interna, pediatría…
CREATE TABLE specialties (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE
);

-- Médicos
CREATE TABLE doctors (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    medical_license VARCHAR(20) NOT NULL UNIQUE,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    institutional_email VARCHAR(120) NOT NULL UNIQUE,
    phone VARCHAR(20) NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- N:M médico–especialidad
CREATE TABLE doctor_specialties (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    specialty_id BIGINT NOT NULL,
    UNIQUE (doctor_id, specialty_id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (specialty_id) REFERENCES specialties(id)
);

-- N:M médico–sede (independiente de la especialidad: 4FN)
CREATE TABLE doctor_sites (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    site_id BIGINT NOT NULL,
    UNIQUE (doctor_id, site_id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (site_id) REFERENCES sites(id)
);

-- ---------------------------------------------------------------------
-- Módulo 3 · Disponibilidad
-- ---------------------------------------------------------------------

-- Horario semanal: día, hora inicio/fin y consultorio
CREATE TABLE doctor_schedules (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    office_id BIGINT NOT NULL,
    day_of_week ENUM('LUNES','MARTES','MIERCOLES','JUEVES','VIERNES','SABADO','DOMINGO') NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    UNIQUE (doctor_id, day_of_week, start_time),
    CHECK (end_time > start_time),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (office_id) REFERENCES offices(id)
);

-- Vacaciones, incapacidad, capacitación…
CREATE TABLE absence_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(40) NOT NULL UNIQUE
);

-- Novedades del médico con fecha de inicio y fin
CREATE TABLE doctor_absences (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    absence_type_id BIGINT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    notes VARCHAR(200) NULL,
    CHECK (end_date >= start_date),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (absence_type_id) REFERENCES absence_types(id)
);

-- ---------------------------------------------------------------------
-- Módulo 4 · Pacientes
-- ---------------------------------------------------------------------

-- CC, TI, CE, PA, PPT…
CREATE TABLE document_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(5) NOT NULL UNIQUE,
    name VARCHAR(60) NOT NULL
);

-- Pacientes
CREATE TABLE patients (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    document_type_id BIGINT NOT NULL,
    document_number VARCHAR(20) NOT NULL,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60) NOT NULL,
    birth_date DATE NOT NULL,
    sex ENUM('FEMENINO','MASCULINO','INTERSEXUAL') NOT NULL,
    address VARCHAR(150) NOT NULL,
    city_id BIGINT NOT NULL,
    email VARCHAR(120) NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (document_type_id, document_number),
    FOREIGN KEY (document_type_id) REFERENCES document_types(id),
    FOREIGN KEY (city_id) REFERENCES cities(id)
);

-- Varios teléfonos; is_primary = 1 en uno solo, NULL en los demás
CREATE TABLE patient_phones (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    phone_type ENUM('CELULAR','FIJO','TRABAJO') NOT NULL,
    is_primary TINYINT NULL CHECK (is_primary = 1),
    UNIQUE (patient_id, phone_number),
    UNIQUE (patient_id, is_primary),
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);

-- Uno o más contactos de emergencia
CREATE TABLE emergency_contacts (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    full_name VARCHAR(120) NOT NULL,
    relationship VARCHAR(40) NOT NULL,
    phone VARCHAR(20) NOT NULL,
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);

-- ---------------------------------------------------------------------
-- Módulo 5 · Aseguramiento
-- ---------------------------------------------------------------------

-- EPS y medicina prepagada
CREATE TABLE insurers (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    nit VARCHAR(15) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL UNIQUE,
    insurer_type ENUM('EPS','PREPAGADA') NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- CONTRIBUTIVO, SUBSIDIADO, PREPAGADA, PARTICULAR con % de copago
CREATE TABLE plans (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(20) NOT NULL UNIQUE,
    copay_percentage DECIMAL(5,2) NOT NULL CHECK (copay_percentage BETWEEN 0 AND 100)
);

-- Historial de afiliaciones; solo una ACTIVA por paciente
CREATE TABLE affiliations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    insurer_id BIGINT NOT NULL,
    plan_id BIGINT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NULL,
    status ENUM('ACTIVA','INACTIVA') NOT NULL DEFAULT 'ACTIVA',
    CHECK (end_date IS NULL OR end_date > start_date),
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (insurer_id) REFERENCES insurers(id),
    FOREIGN KEY (plan_id) REFERENCES plans(id)
);

-- ---------------------------------------------------------------------
-- Módulo 6 · Alergias
-- ---------------------------------------------------------------------

-- Principios activos (penicilina, ibuprofeno…)
CREATE TABLE active_ingredients (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(80) NOT NULL UNIQUE
);

-- Alergias del paciente contra el principio activo
CREATE TABLE patient_allergies (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    active_ingredient_id BIGINT NOT NULL,
    severity ENUM('LEVE','MODERADA','SEVERA') NOT NULL,
    reaction VARCHAR(150) NULL,
    recorded_at DATE NOT NULL,
    UNIQUE (patient_id, active_ingredient_id),
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (active_ingredient_id) REFERENCES active_ingredients(id)
);

-- ---------------------------------------------------------------------
-- Módulo 7 · Agenda
-- ---------------------------------------------------------------------

-- Usuarios del sistema: quién agenda, cancela, cobra
CREATE TABLE system_users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(40) NOT NULL UNIQUE,
    full_name VARCHAR(120) NOT NULL,
    role ENUM('RECEPCION','MEDICO','FACTURACION','AUDITOR','ADMIN','SISTEMA') NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Tipo de cita: define la duración (20, 30 o 40 min)
CREATE TABLE appointment_types (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(60) NOT NULL UNIQUE,
    duration_minutes SMALLINT NOT NULL CHECK (duration_minutes IN (20, 30, 40))
);

-- Catálogo de motivos de cancelación
CREATE TABLE cancellation_reasons (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(60) NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Citas
CREATE TABLE appointments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    patient_id BIGINT NOT NULL,
    doctor_id BIGINT NOT NULL,
    specialty_id BIGINT NOT NULL,
    office_id BIGINT NOT NULL,
    appointment_type_id BIGINT NOT NULL,
    start_at DATETIME NOT NULL,
    status ENUM('PROGRAMADA','CONFIRMADA','ATENDIDA','CANCELADA','NO_ASISTIO') NOT NULL DEFAULT 'PROGRAMADA',
    cancellation_reason_id BIGINT NULL,
    created_by BIGINT NOT NULL,
    updated_by BIGINT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CHECK (status <> 'CANCELADA' OR cancellation_reason_id IS NOT NULL),
    FOREIGN KEY (patient_id) REFERENCES patients(id),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id),
    FOREIGN KEY (specialty_id) REFERENCES specialties(id),
    FOREIGN KEY (office_id) REFERENCES offices(id),
    FOREIGN KEY (appointment_type_id) REFERENCES appointment_types(id),
    FOREIGN KEY (cancellation_reason_id) REFERENCES cancellation_reasons(id),
    FOREIGN KEY (created_by) REFERENCES system_users(id),
    FOREIGN KEY (updated_by) REFERENCES system_users(id)
);

-- Cada cambio de estado: de cuál a cuál, cuándo y quién
CREATE TABLE appointment_status_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    previous_status ENUM('PROGRAMADA','CONFIRMADA','ATENDIDA','CANCELADA','NO_ASISTIO') NULL,
    new_status ENUM('PROGRAMADA','CONFIRMADA','ATENDIDA','CANCELADA','NO_ASISTIO') NOT NULL,
    changed_at DATETIME NOT NULL,
    changed_by BIGINT NOT NULL,
    cancellation_reason_id BIGINT NULL,
    CHECK (new_status <> 'CANCELADA' OR cancellation_reason_id IS NOT NULL),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id),
    FOREIGN KEY (changed_by) REFERENCES system_users(id),
    FOREIGN KEY (cancellation_reason_id) REFERENCES cancellation_reasons(id)
);

-- ---------------------------------------------------------------------
-- Módulo 8 · Seguimiento
-- ---------------------------------------------------------------------

-- Recordatorio del día anterior y si se envió o falló
CREATE TABLE reminders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL,
    channel ENUM('SMS','CORREO','WHATSAPP') NOT NULL,
    scheduled_for DATETIME NOT NULL,
    status ENUM('PENDIENTE','ENVIADO','FALLIDO') NOT NULL DEFAULT 'PENDIENTE',
    sent_at DATETIME NULL,
    UNIQUE (appointment_id, channel),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
);

-- Encuesta de satisfacción: una por cita, de 1 a 5
CREATE TABLE surveys (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE,
    score TINYINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment VARCHAR(300) NULL,
    answered_at DATETIME NOT NULL,
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
);

-- ---------------------------------------------------------------------
-- Módulo 9 · Atención clínica
-- ---------------------------------------------------------------------

-- Atención: lo que pasa cuando el paciente es atendido (1 por cita)
CREATE TABLE attentions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    appointment_id BIGINT NOT NULL UNIQUE,
    started_at DATETIME NOT NULL,
    ended_at DATETIME NULL,
    reason_for_visit VARCHAR(200) NOT NULL,
    notes TEXT NULL,
    CHECK (ended_at IS NULL OR ended_at > started_at),
    FOREIGN KEY (appointment_id) REFERENCES appointments(id)
);

-- Signos vitales con rangos posibles
CREATE TABLE vital_signs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    attention_id BIGINT NOT NULL,
    measured_at DATETIME NOT NULL,
    systolic_bp SMALLINT NOT NULL CHECK (systolic_bp BETWEEN 60 AND 260),
    diastolic_bp SMALLINT NOT NULL CHECK (diastolic_bp BETWEEN 30 AND 160),
    heart_rate SMALLINT NOT NULL CHECK (heart_rate BETWEEN 20 AND 250),
    temperature_c DECIMAL(4,1) NOT NULL CHECK (temperature_c BETWEEN 30 AND 45),
    weight_kg DECIMAL(5,2) NOT NULL CHECK (weight_kg > 0 AND weight_kg <= 400),
    height_cm DECIMAL(5,1) NOT NULL CHECK (height_cm > 0 AND height_cm <= 250),
    CHECK (diastolic_bp < systolic_bp),
    FOREIGN KEY (attention_id) REFERENCES attentions(id)
);

-- Diagnósticos CIE-10 (I10, E11, J06…)
CREATE TABLE cie10_codes (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(7) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL
);

-- Diagnósticos de la atención; is_primary = 1 en uno solo
CREATE TABLE attention_diagnoses (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    attention_id BIGINT NOT NULL,
    cie10_code_id BIGINT NOT NULL,
    is_primary TINYINT NULL CHECK (is_primary = 1),
    UNIQUE (attention_id, cie10_code_id),
    UNIQUE (attention_id, is_primary),
    FOREIGN KEY (attention_id) REFERENCES attentions(id),
    FOREIGN KEY (cie10_code_id) REFERENCES cie10_codes(id)
);

-- Servicios y procedimientos con código CUPS
CREATE TABLE cups_services (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cups_code VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

-- Servicios prestados en la atención (lo que se factura)
CREATE TABLE attention_procedures (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    attention_id BIGINT NOT NULL,
    cups_service_id BIGINT NOT NULL,
    quantity SMALLINT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    UNIQUE (attention_id, cups_service_id),
    FOREIGN KEY (attention_id) REFERENCES attentions(id),
    FOREIGN KEY (cups_service_id) REFERENCES cups_services(id)
);

-- ---------------------------------------------------------------------
-- Módulo 10 · Fórmulas
-- ---------------------------------------------------------------------

-- Medicamentos (marca) con su principio activo
CREATE TABLE medications (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    active_ingredient_id BIGINT NOT NULL,
    commercial_name VARCHAR(100) NOT NULL,
    presentation VARCHAR(60) NOT NULL,
    concentration VARCHAR(40) NOT NULL,
    UNIQUE (commercial_name, presentation, concentration),
    FOREIGN KEY (active_ingredient_id) REFERENCES active_ingredients(id)
);

-- Fórmula médica de una atención
CREATE TABLE prescriptions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    attention_id BIGINT NOT NULL,
    issued_at DATETIME NOT NULL,
    notes VARCHAR(300) NULL,
    FOREIGN KEY (attention_id) REFERENCES attentions(id)
);

-- Renglones de la fórmula: dosis, frecuencia y días
CREATE TABLE prescription_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    prescription_id BIGINT NOT NULL,
    medication_id BIGINT NOT NULL,
    dose VARCHAR(40) NOT NULL,
    frequency VARCHAR(40) NOT NULL,
    duration_days SMALLINT NOT NULL CHECK (duration_days > 0),
    UNIQUE (prescription_id, medication_id),
    FOREIGN KEY (prescription_id) REFERENCES prescriptions(id),
    FOREIGN KEY (medication_id) REFERENCES medications(id)
);

-- ---------------------------------------------------------------------
-- Módulo 11 · Laboratorio
-- ---------------------------------------------------------------------

-- Exámenes con unidad y rango de referencia
CREATE TABLE lab_exams (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    unit VARCHAR(20) NOT NULL,
    reference_min DECIMAL(10,2) NOT NULL,
    reference_max DECIMAL(10,2) NOT NULL,
    CHECK (reference_max > reference_min)
);

-- Orden de laboratorio de una atención
CREATE TABLE lab_orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    attention_id BIGINT NOT NULL,
    ordered_at DATETIME NOT NULL,
    status ENUM('ORDENADA','EN_PROCESO','COMPLETADA') NOT NULL DEFAULT 'ORDENADA',
    FOREIGN KEY (attention_id) REFERENCES attentions(id)
);

-- Exámenes de cada orden
CREATE TABLE lab_order_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    lab_order_id BIGINT NOT NULL,
    lab_exam_id BIGINT NOT NULL,
    UNIQUE (lab_order_id, lab_exam_id),
    FOREIGN KEY (lab_order_id) REFERENCES lab_orders(id),
    FOREIGN KEY (lab_exam_id) REFERENCES lab_exams(id)
);

-- Resultado de cada examen ordenado (0 o 1)
CREATE TABLE lab_results (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    lab_order_item_id BIGINT NOT NULL UNIQUE,
    result_value DECIMAL(10,2) NOT NULL,
    resulted_at DATETIME NOT NULL,
    FOREIGN KEY (lab_order_item_id) REFERENCES lab_order_items(id)
);

-- ---------------------------------------------------------------------
-- Módulo 12 · Facturación
-- ---------------------------------------------------------------------

-- Precio por servicio y plan con vigencia
CREATE TABLE tariffs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    cups_service_id BIGINT NOT NULL,
    plan_id BIGINT NOT NULL,
    price DECIMAL(12,2) NOT NULL CHECK (price > 0),
    valid_from DATE NOT NULL,
    valid_to DATE NOT NULL,
    UNIQUE (cups_service_id, plan_id, valid_from),
    CHECK (valid_to > valid_from),
    FOREIGN KEY (cups_service_id) REFERENCES cups_services(id),
    FOREIGN KEY (plan_id) REFERENCES plans(id)
);

-- Factura: una por atención; nunca se borra
CREATE TABLE invoices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_number VARCHAR(20) NOT NULL UNIQUE,
    attention_id BIGINT NOT NULL UNIQUE,
    affiliation_id BIGINT NULL,
    issued_at DATE NOT NULL,
    copay_percentage DECIMAL(5,2) NOT NULL CHECK (copay_percentage BETWEEN 0 AND 100),
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
    patient_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (patient_amount >= 0),
    insurer_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (insurer_amount >= 0),
    status ENUM('PENDIENTE','PARCIAL','PAGADA','VENCIDA','ANULADA') NOT NULL DEFAULT 'PENDIENTE',
    CHECK (patient_amount + insurer_amount = total_amount),
    FOREIGN KEY (attention_id) REFERENCES attentions(id),
    FOREIGN KEY (affiliation_id) REFERENCES affiliations(id)
);

-- Renglones: servicio, cantidad y precio copiado del día
CREATE TABLE invoice_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    cups_service_id BIGINT NOT NULL,
    quantity SMALLINT NOT NULL CHECK (quantity > 0),
    unit_price DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    UNIQUE (invoice_id, cups_service_id),
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (cups_service_id) REFERENCES cups_services(id)
);

-- Efectivo, tarjeta, transferencia, PSE…
CREATE TABLE payment_methods (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(40) NOT NULL UNIQUE
);

-- Abonos a una factura, siempre mayores que 0
CREATE TABLE payments (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    payment_method_id BIGINT NOT NULL,
    amount DECIMAL(12,2) NOT NULL CHECK (amount > 0),
    paid_at DATETIME NOT NULL,
    reference VARCHAR(50) NULL,
    received_by BIGINT NOT NULL,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (payment_method_id) REFERENCES payment_methods(id),
    FOREIGN KEY (received_by) REFERENCES system_users(id)
);

-- Anulación de factura: fecha, motivo y quién
CREATE TABLE invoice_cancellations (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    invoice_id BIGINT NOT NULL UNIQUE,
    cancelled_at DATETIME NOT NULL,
    reason VARCHAR(200) NOT NULL CHECK (reason <> ''),
    cancelled_by BIGINT NULL,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id),
    FOREIGN KEY (cancelled_by) REFERENCES system_users(id)
);

-- ---------------------------------------------------------------------
-- Módulo 13 · Reportes
-- ---------------------------------------------------------------------

-- Resumen mensual por médico (lo llena E-5)
CREATE TABLE monthly_production_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    doctor_id BIGINT NOT NULL,
    period_year SMALLINT NOT NULL,
    period_month TINYINT NOT NULL CHECK (period_month BETWEEN 1 AND 12),
    attentions_count INT NOT NULL CHECK (attentions_count >= 0),
    billed_amount DECIMAL(12,2) NOT NULL CHECK (billed_amount >= 0),
    generated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (doctor_id, period_year, period_month),
    FOREIGN KEY (doctor_id) REFERENCES doctors(id)
);

-- Verificación rápida: debe decir 46
SELECT COUNT(*) AS total_tablas FROM information_schema.tables WHERE table_schema = 'medicita_ips';
