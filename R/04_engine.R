# =============================================================================
# 04_engine.R  ·  MOTOR de análisis por bloque (funciones reutilizables)
# -----------------------------------------------------------------------------
# Toda la lógica analítica vive aquí UNA sola vez, parametrizada por `blq`
# (A = OIRS, B = participación social, C = satisfacción usuaria). Los runners
# 20/21/22 sólo cargan datos y llaman estas funciones; la síntesis (30) las
# reutiliza. Cada función escribe sus salidas en productos/<blq>/.
#
# El mismo flujo que veníamos usando, ahora aplicado sección por sección:
#   KPIs · cobertura territorial · serie temporal · equidad (sexo/género/
#   migración/pueblos/PRAIS) · subsecciones propias · hurdle mixto ·
#   multinivel 3 niveles · autocorrelación espacial · tipologías k-means.
#
# SALVAGUARDA: los modelos pesados (glmer/lmer/Moran/k-means) van envueltos en
# tryCatch y chequeos de convergencia. Si un bloque es demasiado ralo para un
# modelo, se registra el motivo en productos/<blq>/modelo_estado.csv y el
# pipeline continúa, sin abortar el resto del análisis.
#
# NOTA de diseño: el parámetro se llama `blq` (no `bloque`) a propósito, para no
# colisionar con la columna `bloque` de las tablas dentro de los filtros de
# data.table (evita el bug clásico de auto-comparación columna == columna).
# =============================================================================
suppressPackageStartupMessages({
  library(here)
  library(data.table)
  library(lme4)
})

# nAGQ de los glmer: 1 = Laplace (exacto, ~30-40 min) por defecto;
# REM_FAST="1" usa 0 (PIRLS, ~4 min pero ICC algo subestimado). Iterar rapido
# con REM_FAST=1; la corrida final/publicada se deja en exacto (def).
.nagq <- function() if (Sys.getenv("REM_FAST", unset = "0") == "1") 0L else 1L

# --- Chequeo de ajuste singular (varianza de borde ~ 0; frecuente en region) --
# Las componentes de varianza (ICC, % por nivel, MOR) se reportan como estimaciones
# puntuales por maxima verosimilitud (Laplace). No se computa su IC por bootstrap:
# en estos modelos de 3 niveles con ~3.000 establecimientos es prohibitivo, y es
# practica estandar reportar el punto con el chequeo de singularidad. La
# incertidumbre de los EFECTOS (OR) si se reporta con IC (modelo_determinantes,
# modelo_tipo_or).
.es_singular <- function(m) tryCatch(isTRUE(lme4::isSingular(m)), error = function(e) NA)

# ---- utilitarios -----------------------------------------------------------

dir_bloque <- function(blq) {
  d <- here("productos", blq)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

# Registro de estado de un modelo (convergió / por qué no).
.estado <- function(dirb, modelo, estado, detalle = "") {
  f <- file.path(dirb, "modelo_estado.csv")
  fila <- data.table(modelo = modelo, estado = estado, detalle = detalle,
                     ts = as.character(Sys.time()))
  if (file.exists(f)) fila <- rbind(fread(f, sep = ";"), fila, fill = TRUE)
  fwrite(fila, f, sep = ";", bom = TRUE)
  message(sprintf("  [%s] %s -> %s %s", dirb, modelo, estado,
                  if (nzchar(detalle)) paste0("(", detalle, ")") else ""))
}

# Agrupación de tipo de establecimiento (top 8 + Otro).
tipo_agrupado <- function(est) {
  principales <- c("Posta de Salud Rural (PSR)", "Centro de Salud Familiar (CESFAM)",
    "Centro Comunitario de Salud Familiar (CECOSF)",
    "Servicio de Atención Primaria de Urgencia (SAPU)", "Hospital",
    "Servicio de Urgencia Rural (SUR)", "Centro Comunitario de Salud Mental  (COSAM)",
    "Servicio de Atención Primaria de Urgencia de Alta Resolutividad (SAR)")
  corto <- c("Posta Rural (PSR)", "CESFAM", "CECOSF", "SAPU", "Hospital",
             "SUR", "COSAM", "SAR")
  names(corto) <- principales
  est[, tipo_grp := ifelse(TipoEstablecimientoGlosa %in% principales,
                           corto[TipoEstablecimientoGlosa], "Otro")]
  est[is.na(tipo_grp), tipo_grp := "Otro"]
  # Nivel de atencion (limpio) desde la glosa oficial del DEIS.
  if ("NivelAtencionEstabglosa" %in% names(est)) {
    na_glosa <- est$NivelAtencionEstabglosa
    est[, nivel_atencion := fcase(
      grepl("primar",   na_glosa, ignore.case = TRUE), "Primario (APS)",
      grepl("secundar", na_glosa, ignore.case = TRUE), "Secundario",
      grepl("terciar",  na_glosa, ignore.case = TRUE), "Terciario",
      default = "No aplica / otro")]
  } else est[, nivel_atencion := "No aplica / otro"]
  # Universo participativo: urgencias (SAPU/SUR/SAR) casi no registran
  # participacion por diseno de su funcion -> ceros estructurales, no subregistro.
  est[, participa_estructural := !(tipo_grp %in% c("SAPU", "SUR", "SAR"))]
  # Servicio de Salud (red operativa) para el analisis de efecto red.
  if ("SeremiSaludGlosa_ServicioDeSaludGlosa" %in% names(est))
    est[, servicio_salud := SeremiSaludGlosa_ServicioDeSaludGlosa]
  else est[, servicio_salud := NA_character_]
  # Dependencia administrativa limpia (Municipal, Servicio de Salud, etc.).
  if ("DependenciaAdministrativa" %in% names(est))
    est[, dependencia := fifelse(is.na(DependenciaAdministrativa) |
                                 DependenciaAdministrativa == "",
                                 "Sin dato", as.character(DependenciaAdministrativa))]
  else est[, dependencia := "Sin dato"]
  # Reclasificacion de nivel "No aplica / otro": inferir por tipo cuando la glosa
  # oficial no trae nivel. Hospital -> Terciario; centros APS y urgencias de APS
  # -> Primario (APS). Se conserva el original en nivel_atencion_orig (auditable).
  est[, nivel_atencion_orig := nivel_atencion]
  est[nivel_atencion == "No aplica / otro" & tipo_grp == "Hospital",
      nivel_atencion := "Terciario"]
  est[nivel_atencion == "No aplica / otro" &
      tipo_grp %in% c("CESFAM", "CECOSF", "Posta Rural (PSR)", "SAPU",
                      "SUR", "SAR", "COSAM"),
      nivel_atencion := "Primario (APS)"]
  diag <- est[, .(n = .N), by = .(tipo_grp, nivel_atencion_orig, nivel_atencion)][order(-n)]
  dir.create(here("productos"), showWarnings = FALSE, recursive = TRUE)
  fwrite(diag, here("productos", "diagnostico_nivel.csv"), sep = ";", bom = TRUE)
  est[]
}

# Tipo de solicitud OIRS (bloque A): separa reclamos de consultas, felicitaciones,
# sugerencias y solicitudes (cada uno se entiende en su propia logica).
tipo_solicitud_A <- function(desc) {
  d <- tolower(desc)
  fcase(
    grepl("reclamo", d),       "Reclamos",
    grepl("consulta", d),      "Consultas",
    grepl("felicitacion", d),  "Felicitaciones",
    grepl("sugerencia", d),    "Sugerencias",
    grepl("solicitud", d),     "Solicitudes",
    default = "Otros")
}

# Equidad por SUBSECCION (B.1 vs B.2, C.1 vs C.2): perfil de participante de cada
# linea por separado. Los participantes son columnas marginales por subseccion
# (no hay cruce instancia x participante en el dato crudo).
equidad_subseccion <- function(largo, blq, dirb) {
  secs <- switch(blq, A = "A", B = c("B.1", "B.2"), C = c("C.1", "C.2"), blq)
  out <- list()
  for (sk in secs) {
    lg <- largo[seccion_key == sk]
    if (nrow(lg) == 0) next
    tot <- lg[dimension == "total" & grepl("ambos sexos", etiqueta, ignore.case = TRUE),
              sum(valor, na.rm = TRUE)]; tot <- max(tot, 1)
    sx <- lg[dimension == "sexo", .(p = sum(valor, na.rm = TRUE)), by = etiqueta]
    sx[etiqueta == "Masculino", etiqueta := "Hombres"]
    sx[etiqueta == "Femenina",  etiqueta := "Mujeres"]
    sx <- sx[etiqueta %in% c("Hombres", "Mujeres"), .(p = sum(p)), by = etiqueta]
    hb <- sx[etiqueta == "Hombres", sum(p)]; mj <- sx[etiqueta == "Mujeres", sum(p)]
    g <- function(dim) lg[dimension == dim, sum(valor, na.rm = TRUE)]
    out[[sk]] <- data.table(
      seccion = sk, total_personas = tot, hombres = hb, mujeres = mj,
      pct_mujeres = round(100 * mj / max(hb + mj, 1), 1),
      pct_pueblos_originarios = round(100 * g("pueblos_originarios") / tot, 1),
      pct_migrantes = round(100 * g("migrantes") / tot, 1),
      pct_prais = round(100 * g("prais") / tot, 1))
    gen <- lg[dimension == "identidad_genero",
              .(personas = sum(valor, na.rm = TRUE)), by = etiqueta][order(-personas)]
    if (nrow(gen))
      fwrite(gen, file.path(dirb, sprintf("equidad_genero_%s.csv", gsub("\\.", "", sk))),
             sep = ";", bom = TRUE)
  }
  if (length(out))
    fwrite(rbindlist(out), file.path(dirb, "equidad_subseccion.csv"), sep = ";", bom = TRUE)
  invisible(TRUE)
}

# Factor de tipo con CESFAM como referencia (si está presente).
.factor_tipo <- function(x) {
  f <- factor(x)
  if ("CESFAM" %in% levels(f)) f <- relevel(f, ref = "CESFAM")
  f
}

# ---- 1. Panel establecimiento × mes del bloque -----------------------------
# valor = suma de valor_total (Col01 de cada prestación) del bloque, por
# establecimiento y mes. reporta = 1 si registró algo ese mes.
construir_panel <- function(part, est, universo, blq) {
  panel <- copy(universo)
  pt <- part[bloque == blq, .(valor = sum(valor_total, na.rm = TRUE)),
             by = .(IdEstablecimiento, Mes)]
  panel <- merge(panel, pt, by = c("IdEstablecimiento", "Mes"),
                 all.x = TRUE, sort = FALSE)
  panel[is.na(valor), valor := 0]
  panel <- merge(panel, est[, .(IdEstablecimiento, tipo_grp, nivel_atencion, dependencia, servicio_salud, participa_estructural)],
                 by = "IdEstablecimiento", all.x = TRUE, sort = FALSE)
  panel[is.na(tipo_grp), tipo_grp := "Otro"]
  panel[is.na(nivel_atencion), nivel_atencion := "No aplica / otro"]
  panel[is.na(dependencia), dependencia := "Sin dato"]
  panel[is.na(servicio_salud), servicio_salud := "Sin dato"]
  panel[is.na(participa_estructural), participa_estructural := FALSE]
  panel[, reporta := as.integer(valor > 0)]
  panel[]
}

# ---- 2. KPIs del bloque ----------------------------------------------------
kpis_bloque <- function(part, est, panel, largo, blq, dirb) {
  pb <- part[bloque == blq]
  estab_part <- unique(pb$IdEstablecimiento)
  n_estab_total <- est[, uniqueN(IdEstablecimiento)]
  total_personas <- largo[bloque == blq & dimension == "total" &
                          grepl("ambos sexos", etiqueta, ignore.case = TRUE),
                          sum(valor, na.rm = TRUE)]
  reg <- panel[reporta == 1, .N, by = IdEstablecimiento]  # meses con registro
  k <- data.table(
    indicador = c("establecimientos_activos", "establecimientos_participan",
                  "pct_cobertura", "prestaciones_monitoreadas",
                  "total_eventos", "total_personas", "intensidad_por_estab",
                  "pct_subregistro_estab_mes", "mediana_meses_con_registro"),
    valor = c(
      n_estab_total,
      length(estab_part),
      round(100 * length(estab_part) / max(n_estab_total, 1), 1),
      uniqueN(pb$CodigoPrestacion),
      sum(pb$valor_total, na.rm = TRUE),
      total_personas,
      round(sum(pb$valor_total, na.rm = TRUE) / max(length(estab_part), 1), 1),
      round(100 * mean(panel$reporta == 0), 1),
      ifelse(nrow(reg) > 0, as.numeric(median(reg$N)), 0)))
  fwrite(k, file.path(dirb, "kpis.csv"), sep = ";", bom = TRUE)
  k
}

# ---- 3. Cobertura territorial ----------------------------------------------
cobertura_territorial <- function(est, part, blq, dirb) {
  estab_part <- unique(part[bloque == blq]$IdEstablecimiento)
  e <- copy(est)
  e[, participa := IdEstablecimiento %in% estab_part]
  cob <- function(by_col) e[!is.na(get(by_col)),
    .(n_total = .N, n_participa = sum(participa),
      pct = round(100 * mean(participa), 1)), by = by_col]
  fwrite(cob("IdRegion")[order(IdRegion)],
         file.path(dirb, "cobertura_region.csv"), sep = ";", bom = TRUE)
  fwrite(cob("ComunaGlosa")[order(-pct)],
         file.path(dirb, "cobertura_comuna.csv"), sep = ";", bom = TRUE)
  fwrite(cob("tipo_grp")[order(-pct)],
         file.path(dirb, "cobertura_tipo.csv"), sep = ";", bom = TRUE)
  fwrite(cob("DependenciaAdministrativa")[order(-pct)],
         file.path(dirb, "cobertura_dependencia.csv"), sep = ";", bom = TRUE)
  if ("servicio_salud" %in% names(e))
    fwrite(cob("servicio_salud")[order(-pct)],
           file.path(dirb, "cobertura_servicio.csv"), sep = ";", bom = TRUE)
  invisible(TRUE)
}

# ---- 4. Serie temporal mensual (por subsección) ----------------------------
serie_temporal <- function(part, blq, dirb) {
  pb <- part[bloque == blq]
  s <- pb[, .(eventos = sum(valor_total, na.rm = TRUE),
              estab_que_reportan = uniqueN(IdEstablecimiento)),
          by = .(Mes, seccion_key)][order(seccion_key, Mes)]
  fwrite(s, file.path(dirb, "serie_mensual.csv"), sep = ";", bom = TRUE)
  invisible(s)
}

# ---- 5. Equidad: sexo / género / migración / pueblos / PRAIS ---------------
equidad_bloque <- function(largo, blq, dirb) {
  lb <- largo[bloque == blq]
  total_personas <- lb[dimension == "total" &
                       grepl("ambos sexos", etiqueta, ignore.case = TRUE),
                       sum(valor, na.rm = TRUE)]
  total_personas <- max(total_personas, 1)

  # Sexo (unificando Masculino->Hombres, Femenina->Mujeres).
  sexo <- lb[dimension == "sexo", .(personas = sum(valor, na.rm = TRUE)), by = etiqueta]
  sexo[etiqueta == "Masculino", etiqueta := "Hombres"]
  sexo[etiqueta == "Femenina",  etiqueta := "Mujeres"]
  sexo <- sexo[etiqueta %in% c("Hombres", "Mujeres"),
               .(personas = sum(personas)), by = etiqueta]
  fwrite(sexo[order(-personas)], file.path(dirb, "equidad_sexo.csv"),
         sep = ";", bom = TRUE)

  # Identidad de género.
  gen <- lb[dimension == "identidad_genero",
            .(personas = sum(valor, na.rm = TRUE)), by = etiqueta][order(-personas)]
  fwrite(gen, file.path(dirb, "equidad_genero.csv"), sep = ";", bom = TRUE)

  # Grupos prioritarios (sólo bloque A: NNA, gestantes).
  grp <- lb[dimension == "grupo_prioritario",
            .(personas = sum(valor, na.rm = TRUE)), by = etiqueta][order(-personas)]
  if (nrow(grp) > 0)
    fwrite(grp, file.path(dirb, "equidad_grupos.csv"), sep = ";", bom = TRUE)

  # KPIs de inclusión.
  g <- function(dim) lb[dimension == dim, sum(valor, na.rm = TRUE)]
  hb <- sexo[etiqueta == "Hombres", sum(personas)]
  mj <- sexo[etiqueta == "Mujeres", sum(personas)]
  base_sexo <- max(hb + mj, 1)
  eq <- data.table(
    indicador = c("total_personas", "pct_hombres", "pct_mujeres", "brecha_genero_pp",
                  "pct_pueblos_originarios", "pct_migrantes", "pct_prais"),
    valor = c(total_personas,
              round(100 * hb / base_sexo, 1),
              round(100 * mj / base_sexo, 1),
              round(100 * (mj - hb) / base_sexo, 1),
              round(100 * g("pueblos_originarios") / total_personas, 1),
              round(100 * g("migrantes") / total_personas, 1),
              round(100 * g("prais") / total_personas, 1)))
  fwrite(eq, file.path(dirb, "equidad_kpis.csv"), sep = ";", bom = TRUE)

  # Equidad por región (migrantes y pueblos originarios).
  po  <- lb[dimension == "pueblos_originarios", .(pueblos_originarios = sum(valor)), by = IdRegion]
  mig <- lb[dimension == "migrantes", .(migrantes = sum(valor)), by = IdRegion]
  per <- lb[dimension == "total" & grepl("ambos sexos", etiqueta, ignore.case = TRUE),
            .(personas = sum(valor)), by = IdRegion]
  eqr <- Reduce(function(a, b) merge(a, b, by = "IdRegion", all = TRUE),
                list(po, mig, per))
  for (j in names(eqr)) set(eqr, which(is.na(eqr[[j]])), j, 0)
  eqr[, pct_pueblos_originarios := round(100 * pueblos_originarios / pmax(personas, 1), 1)]
  eqr[, pct_migrantes := round(100 * migrantes / pmax(personas, 1), 1)]
  fwrite(eqr[order(-pct_migrantes)], file.path(dirb, "equidad_region.csv"),
         sep = ";", bom = TRUE)
  invisible(eq)
}

# ---- 6. Subsecciones propias de cada bloque --------------------------------
# A  -> motivos de reclamo (familias) + gestión de plazos.
# B  -> B.1 instancias  +  B.2 líneas de acción (prestaciones).
# C  -> C.1 líneas de satisfacción  +  C.2 líneas de acción (prestaciones).
familia_reclamo <- function(desc) {
  d <- tolower(desc)
  fcase(
    grepl("^trato", d), "Trato",
    grepl("competencia t|eventos adversos", d), "Competencia/Seguridad",
    grepl("infraestructura|acompañamiento", d), "Infraestructura",
    grepl("tiempo de espera", d), "Tiempos de espera",
    grepl("informaci", d), "Información",
    grepl("procedimientos administrativos", d), "Proc. administrativos",
    grepl("probidad|incumplimiento|garant|vulneraci|violencia|ley", d), "Garantías/Probidad/Derechos",
    grepl("consulta", d), "Consultas",
    grepl("sugerencia", d), "Sugerencias",
    grepl("felicitacion", d), "Felicitaciones",
    grepl("solicitud", d), "Solicitudes",
    default = "Otros")
}

# Cobertura/intensidad por instancia a partir de una tabla larga ya filtrada.
.instancias_intensidad <- function(lg, n_estab_total) {
  inst <- lg[dimension == "instancia",
             .(actividades = sum(valor, na.rm = TRUE),
               n_estab = uniqueN(IdEstablecimiento[!is.na(valor) & valor > 0])),
             by = etiqueta]
  inst[, intensidad := round(actividades / pmax(n_estab, 1), 1)]
  inst[, cobertura := round(100 * n_estab / max(n_estab_total, 1), 1)]
  setorder(inst, -actividades)
  inst
}

# Clasifica las instancias de participacion social (B) por su caracter:
# deliberativa/organica (nucleo del derecho: consejos, cabildos, CDL, COSOC,
# indigena, jovenes, CIRA, comites), informativa (TICs/redes, un canal de
# comunicacion, NO deliberacion) e inespecifica (el cajon "Otras"). Separar TICs
# y "Otras" evita inflar la participacion deliberativa real.
clase_instancia <- function(et) {
  e <- tolower(et)
  fcase(
    grepl("tics|redes sociales", e),      "Informativa (TICs)",
    grepl("otras instancias|^otras", e),  "Inespecifica (Otras)",
    default = "Deliberativa")
}

subsecciones_bloque <- function(largo, part, blq, dirb) {
  n_estab_total <- uniqueN(part[bloque == blq]$IdEstablecimiento)
  if (blq == "A") {
    pb <- part[bloque == "A"]
    fam <- pb[, .(eventos = sum(valor_total, na.rm = TRUE),
                  n_estab = uniqueN(IdEstablecimiento[valor_total > 0])),
              by = .(familia = familia_reclamo(descripcion))][order(-eventos)]
    fwrite(fam, file.path(dirb, "sub_motivos_reclamo.csv"), sep = ";", bom = TRUE)
    gest <- largo[bloque == "A" & dimension == "reclamo_gestion",
                  .(total = sum(valor, na.rm = TRUE)), by = etiqueta][order(-total)]
    fwrite(gest, file.path(dirb, "sub_gestion_reclamos.csv"), sep = ";", bom = TRUE)
    # A se entiende por TIPO de solicitud (no todo es "reclamo").
    tip <- pb[, .(eventos = sum(valor_total, na.rm = TRUE),
                  n_estab = uniqueN(IdEstablecimiento[valor_total > 0])),
              by = .(tipo = tipo_solicitud_A(descripcion))][order(-eventos)]
    fwrite(tip, file.path(dirb, "sub_A_tipos_solicitud.csv"), sep = ";", bom = TRUE)
    gv <- function(t) tip[tipo == t, sum(eventos)]
    # Los reclamos reales NO llevan la palabra "reclamo" en la glosa de la
    # prestacion (van por motivo): se toman de la gestion ("Reclamos generados
    # en el mes"). El grep literal solo captura una fraccion marginal.
    rec <- gest[grepl("generados en el mes$", etiqueta), sum(total)]
    if (length(rec) == 0 || is.na(rec) || rec == 0) rec <- gv("Reclamos")
    fel <- gv("Felicitaciones")
    fwrite(data.table(
      indicador = c("total_reclamos", "total_consultas", "total_felicitaciones",
                    "total_sugerencias", "total_solicitudes",
                    "razon_felicitaciones_reclamos"),
      valor = c(rec, gv("Consultas"), fel, gv("Sugerencias"), gv("Solicitudes"),
                round(fel / max(rec, 1), 3))),
      file.path(dirb, "kpis_A_tipos.csv"), sep = ";", bom = TRUE)

  } else if (blq == "B") {
    inst <- .instancias_intensidad(largo[seccion_key == "B.1"], n_estab_total)
    inst[, clase := clase_instancia(etiqueta)]
    fwrite(inst, file.path(dirb, "sub_b1_instancias.csv"), sep = ";", bom = TRUE)
    # Reparto de la actividad por clase (deliberativa / TICs / Otras).
    # n_estab por clase = establecimientos UNICOS (sumar por instancia los
    # contaria varias veces y puede superar el total de la red).
    lg_cl <- largo[seccion_key == "B.1" & dimension == "instancia" & valor > 0]
    lg_cl[, clase := clase_instancia(etiqueta)]
    cl_estab <- lg_cl[, .(n_estab = uniqueN(IdEstablecimiento)), by = clase]
    clase_tot <- inst[, .(actividades = sum(actividades)), by = clase]
    clase_tot <- merge(clase_tot, cl_estab, by = "clase", all.x = TRUE)[order(-actividades)]
    clase_tot[, pct_actividades := round(100 * actividades / sum(actividades), 1)]
    fwrite(clase_tot, file.path(dirb, "sub_b1_clase.csv"), sep = ";", bom = TRUE)
    # KPIs del NUCLEO DELIBERATIVO (excluye TICs y "Otras"), para no inflar la cifra.
    lg1 <- largo[seccion_key == "B.1" & dimension == "instancia" & valor > 0]
    lg1[, clase := clase_instancia(etiqueta)]
    estab_del <- lg1[clase == "Deliberativa", uniqueN(IdEstablecimiento)]
    act_del   <- lg1[clase == "Deliberativa", sum(valor, na.rm = TRUE)]
    act_tot   <- max(lg1[, sum(valor, na.rm = TRUE)], 1)
    act_tics  <- lg1[clase == "Informativa (TICs)", sum(valor, na.rm = TRUE)]
    act_otr   <- lg1[clase == "Inespecifica (Otras)", sum(valor, na.rm = TRUE)]
    # Denominador de RED COMPLETA (establecimientos_activos de kpis.csv, ya
    # escrito por kpis_bloque). El denominador "solo participantes" sobreestima
    # la cobertura deliberativa; se reportan ambos, etiquetados sin ambiguedad.
    estab_red <- {
      kf <- file.path(dirb, "kpis.csv")
      if (file.exists(kf)) {
        kk <- fread(kf, sep = ";", encoding = "UTF-8")
        as.numeric(kk[indicador == "establecimientos_activos", valor][1])
      } else NA_real_
    }
    fwrite(data.table(
      indicador = c("cobertura_deliberativa_pct",
                    "cobertura_deliberativa_entre_participantes_pct",
                    "establecimientos_deliberativos",
                    "actividades_deliberativas", "intensidad_deliberativa",
                    "pct_actividades_deliberativas", "pct_actividades_tics",
                    "pct_actividades_otras"),
      valor = c(round(100 * estab_del / max(estab_red, 1, na.rm = TRUE), 1),
                round(100 * estab_del / max(n_estab_total, 1), 1), estab_del,
                act_del, round(act_del / max(estab_del, 1), 1),
                round(100 * act_del / act_tot, 1),
                round(100 * act_tics / act_tot, 1),
                round(100 * act_otr / act_tot, 1))),
      file.path(dirb, "kpis_B_nucleo.csv"), sep = ";", bom = TRUE)
    lineas <- part[seccion_key == "B.2",
                   .(sesiones = sum(valor_total, na.rm = TRUE),
                     n_estab = uniqueN(IdEstablecimiento[valor_total > 0])),
                   by = .(linea = descripcion)][order(-sesiones)]
    fwrite(lineas, file.path(dirb, "sub_b2_lineas_accion.csv"), sep = ";", bom = TRUE)

  } else if (blq == "C") {
    lineas_sat <- largo[seccion_key == "C.1" &
                        dimension %in% c("linea_satisfaccion", "instancia"),
                        .(total = sum(valor, na.rm = TRUE)), by = etiqueta][order(-total)]
    fwrite(lineas_sat, file.path(dirb, "sub_c1_lineas_satisfaccion.csv"),
           sep = ";", bom = TRUE)
    lineas <- part[seccion_key == "C.2",
                   .(sesiones = sum(valor_total, na.rm = TRUE),
                     n_estab = uniqueN(IdEstablecimiento[valor_total > 0])),
                   by = .(linea = descripcion)][order(-sesiones)]
    fwrite(lineas, file.path(dirb, "sub_c2_lineas_accion.csv"), sep = ";", bom = TRUE)
  }
  invisible(TRUE)
}

# ---- 7. Hurdle mixto: barrera (glmer) + intensidad (lmer) -------------------
modelo_hurdle <- function(panel, blq, dirb) {
  d <- copy(panel)[!is.na(tipo_grp)]
  if (d[, sum(reporta)] < 30 || d[reporta == 1, uniqueN(IdEstablecimiento)] < 20) {
    .estado(dirb, "hurdle", "omitido", "muy pocos positivos para estimar")
    return(invisible(FALSE))
  }
  d[, `:=`(IdRegion = factor(IdRegion), Mes = factor(Mes, levels = 1:12),
           tipo_grp = .factor_tipo(tipo_grp),
           IdEstablecimiento = factor(IdEstablecimiento))]

  m_b <- tryCatch(
    glmer(reporta ~ IdRegion + tipo_grp + Mes + (1 | IdEstablecimiento),
          family = binomial, data = d, nAGQ = .nagq(),
          control = glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))),
    error = function(e) { .estado(dirb, "hurdle_barrera", "error", conditionMessage(e)); NULL })

  pos <- d[valor > 0]; pos[, log_valor := log(valor)]
  m_i <- tryCatch(
    lmer(log_valor ~ IdRegion + tipo_grp + Mes + (1 | IdEstablecimiento), data = pos),
    error = function(e) { .estado(dirb, "hurdle_intensidad", "error", conditionMessage(e)); NULL })

  if (is.null(m_b)) return(invisible(FALSE))
  vb <- as.numeric(VarCorr(m_b)$IdEstablecimiento); icc_b <- vb / (vb + pi^2 / 3)
  icc_i <- NA_real_
  if (!is.null(m_i)) {
    vci <- as.data.frame(VarCorr(m_i))
    icc_i <- vci[vci$grp == "IdEstablecimiento", "vcov"] /
      (vci[vci$grp == "IdEstablecimiento", "vcov"] + vci[vci$grp == "Residual", "vcov"])
  }
  # MOR (median odds ratio): traduce la varianza de establecimiento a escala OR.
  mor <- exp(sqrt(2 * vb) * qnorm(0.75))
  sing_b <- .es_singular(m_b)
  # ICC y MOR son CONDICIONALES a los efectos fijos (region, tipo, mes): miden la
  # varianza de establecimiento no explicada por esas covariables. Estimacion
  # puntual (sin IC por bootstrap; ver nota en la cabecera del motor).
  fwrite(data.table(
    indicador = c("icc_barrera_pct", "icc_intensidad_pct", "MOR_establecimiento",
                  "ajuste_singular_barrera"),
    valor = c(round(100 * icc_b, 1), round(100 * icc_i, 1), round(mor, 2),
              ifelse(isTRUE(sing_b), 1, ifelse(is.na(sing_b), NA, 0)))),
    file.path(dirb, "modelo_icc.csv"), sep = ";", bom = TRUE)
  if (isTRUE(sing_b)) .estado(dirb, "hurdle_barrera", "singular", "ajuste de borde: varianza ~ 0")
  d[, p := predict(m_b, newdata = d, re.form = NA, type = "response")]
  fwrite(d[, .(prob_registra = round(mean(p), 3)), by = IdRegion][order(-prob_registra)],
         file.path(dirb, "modelo_region.csv"), sep = ";", bom = TRUE)
  fwrite(d[, .(prob_registra = round(mean(p), 3)), by = tipo_grp][order(-prob_registra)],
         file.path(dirb, "modelo_tipo.csv"), sep = ";", bom = TRUE)
  if ("nivel_atencion" %in% names(d))
    fwrite(d[, .(prob_registra = round(mean(p), 3)), by = nivel_atencion][order(-prob_registra)],
           file.path(dirb, "modelo_nivel.csv"), sep = ";", bom = TRUE)
  if ("dependencia" %in% names(d))
    fwrite(d[, .(prob_registra = round(mean(p), 3)), by = dependencia][order(-prob_registra)],
           file.path(dirb, "modelo_dependencia.csv"), sep = ";", bom = TRUE)
  if ("IdComuna" %in% names(d))
    fwrite(d[, .(prob_registra = round(mean(p), 3), n = .N), by = IdComuna][order(-prob_registra)],
           file.path(dirb, "modelo_comuna.csv"), sep = ";", bom = TRUE)
  # OR de cada tipo vs CESFAM (efecto fijo de la barrera): quien reporta mas.
  co_b <- tryCatch(summary(m_b)$coefficients, error = function(e) NULL)
  if (!is.null(co_b)) {
    rn <- rownames(co_b); idx <- grep("^tipo_grp", rn)
    if (length(idx))
      fwrite(data.table(
        tipo = sub("^tipo_grp", "", rn[idx]),
        OR_vs_CESFAM = round(exp(co_b[idx, "Estimate"]), 2),
        IC95_inf = round(exp(co_b[idx, "Estimate"] - 1.96 * co_b[idx, "Std. Error"]), 2),
        IC95_sup = round(exp(co_b[idx, "Estimate"] + 1.96 * co_b[idx, "Std. Error"]), 2),
        p_valor = round(co_b[idx, "Pr(>|z|)"], 4))[order(-OR_vs_CESFAM)],
        file.path(dirb, "modelo_tipo_or.csv"), sep = ";", bom = TRUE)
  }
  mmes <- d[, .(prob_registra = round(mean(p), 3)), by = Mes]
  mmes[, Mes := as.integer(as.character(Mes))]
  fwrite(mmes[order(Mes)], file.path(dirb, "modelo_estacionalidad.csv"), sep = ";", bom = TRUE)
  .estado(dirb, "hurdle", "ok",
          sprintf("ICC barrera %.1f%% / intensidad %.1f%%", 100 * icc_b, 100 * icc_i))
  invisible(TRUE)
}

# ---- 8. Multinivel 3 niveles (región/comuna/establecimiento) + pobreza -----
modelo_multinivel <- function(panel, com, est, part, blq, dirb) {
  d <- merge(panel, com[, .(IdComuna, pct_pobreza)], by = "IdComuna",
             all.x = TRUE, sort = FALSE)
  d <- d[!is.na(pct_pobreza) & !is.na(tipo_grp)]
  if (d[, sum(reporta)] < 30) {
    .estado(dirb, "multinivel", "omitido", "muy pocos positivos")
    return(invisible(FALSE))
  }
  d[, `:=`(pobreza10 = pct_pobreza / 10, Mes = factor(Mes, levels = 1:12),
           tipo_grp = .factor_tipo(tipo_grp),
           IdRegion = factor(IdRegion), IdComuna = factor(IdComuna),
           IdEstablecimiento = factor(IdEstablecimiento))]

  m <- tryCatch(
    glmer(reporta ~ tipo_grp + pobreza10 + Mes +
            (1 | IdRegion / IdComuna / IdEstablecimiento),
          family = binomial, data = d, nAGQ = .nagq(),
          control = glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 3e5))),
    error = function(e) { .estado(dirb, "multinivel", "error", conditionMessage(e)); NULL })
  if (is.null(m)) return(invisible(FALSE))

  vc <- as.data.frame(VarCorr(m))
  v_est <- sum(vc$vcov[grepl("IdEstablecimiento", vc$grp)])
  v_com <- sum(vc$vcov[grepl("IdComuna", vc$grp) & !grepl("IdEstablecimiento", vc$grp)])
  v_reg <- sum(vc$vcov[vc$grp == "IdRegion"])
  v_res <- pi^2 / 3
  tot <- v_est + v_com + v_reg + v_res
  sing_m <- .es_singular(m)
  # Particion de varianza (VPC) condicional a los efectos fijos. Estimacion
  # puntual; sin IC por bootstrap (ver nota en la cabecera del motor).
  fwrite(data.table(
    nivel = c("Establecimiento", "Comuna", "Región", "Residual (mes a mes)"),
    pct_varianza = round(100 * c(v_est, v_com, v_reg, v_res) / tot, 1),
    ajuste_singular = c(ifelse(isTRUE(sing_m), 1, ifelse(is.na(sing_m), NA, 0)), NA, NA, NA)),
    file.path(dirb, "modelo_multinivel_var.csv"), sep = ";", bom = TRUE)
  if (isTRUE(sing_m)) .estado(dirb, "multinivel", "singular", "ajuste de borde: varianza de region ~ 0 (esperable)")

  co <- summary(m)$coefficients
  if ("pobreza10" %in% rownames(co)) {
    or <- exp(co["pobreza10", "Estimate"])
    lo <- exp(co["pobreza10", "Estimate"] - 1.96 * co["pobreza10", "Std. Error"])
    hi <- exp(co["pobreza10", "Estimate"] + 1.96 * co["pobreza10", "Std. Error"])
    fwrite(data.table(indicador = c("OR_pobreza_x10pp", "IC95_inferior",
                                    "IC95_superior", "p_valor"),
                      valor = round(c(or, lo, hi, co["pobreza10", "Pr(>|z|)"]), 4)),
           file.path(dirb, "modelo_determinantes.csv"), sep = ";", bom = TRUE)
  }

  # --- Red vs geografia: mismo modelo con Servicio de Salud arriba en vez de region.
  # Si la red explica mas varianza que la region, "lo territorial" es gestion de red.
  if ("servicio_salud" %in% names(d) &&
      d[!is.na(servicio_salud) & servicio_salud != "Sin dato", uniqueN(servicio_salud)] > 1) {
    ds <- droplevels(d[!is.na(servicio_salud) & servicio_salud != "Sin dato"])
    ds[, servicio_salud := factor(servicio_salud)]
    ms <- tryCatch(
      glmer(reporta ~ tipo_grp + pobreza10 + Mes +
              (1 | servicio_salud / IdComuna / IdEstablecimiento),
            family = binomial, data = ds, nAGQ = .nagq(),
            control = glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 3e5))),
      error = function(e) { .estado(dirb, "multinivel_servicio", "error", conditionMessage(e)); NULL })
    if (!is.null(ms)) {
      vcs <- as.data.frame(VarCorr(ms))
      e2 <- sum(vcs$vcov[grepl("IdEstablecimiento", vcs$grp)])
      c2 <- sum(vcs$vcov[grepl("IdComuna", vcs$grp) & !grepl("IdEstablecimiento", vcs$grp)])
      s2 <- sum(vcs$vcov[vcs$grp == "servicio_salud"])
      r2 <- pi^2 / 3; t2 <- e2 + c2 + s2 + r2
      fwrite(data.table(
        nivel = c("Establecimiento", "Comuna", "Servicio de Salud", "Residual (mes a mes)"),
        pct_varianza = round(100 * c(e2, c2, s2, r2) / t2, 1)),
        file.path(dirb, "modelo_multinivel_var_servicio.csv"), sep = ";", bom = TRUE)
      .estado(dirb, "multinivel_servicio", "ok",
              sprintf("var Servicio de Salud %.1f%% (comuna %.1f%%, region era %.1f%%)",
                      100 * s2 / t2, 100 * c2 / t2, round(100 * v_reg / tot, 1)))
    }
  }

  # --- Sensibilidad: universo participativo (excluye urgencias estructurales) ---
  # Responde "¿cambia la pobreza/territorio al quitar los ceros estructurales?".
  d2 <- droplevels(d[participa_estructural == TRUE])
  hacer_sens <- Sys.getenv("REM_SENS", unset = "1") == "1"
  if (hacer_sens && nrow(d2) > 0 && sum(d2$reporta) >= 30) {
    m2 <- tryCatch(
      glmer(reporta ~ tipo_grp + pobreza10 + Mes +
              (1 | IdRegion / IdComuna / IdEstablecimiento),
            family = binomial, data = d2, nAGQ = .nagq(),
            control = glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 3e5))),
      error = function(e) { .estado(dirb, "multinivel_part", "error", conditionMessage(e)); NULL })
    if (!is.null(m2)) {
      vc2 <- as.data.frame(VarCorr(m2))
      ve2 <- sum(vc2$vcov[grepl("IdEstablecimiento", vc2$grp)])
      vco2 <- sum(vc2$vcov[grepl("IdComuna", vc2$grp) & !grepl("IdEstablecimiento", vc2$grp)])
      vr2 <- sum(vc2$vcov[vc2$grp == "IdRegion"]); vres2 <- pi^2 / 3
      tot2 <- ve2 + vco2 + vr2 + vres2
      fwrite(data.table(nivel = c("Establecimiento", "Comuna", "Región", "Residual (mes a mes)"),
                        pct_varianza = round(100 * c(ve2, vco2, vr2, vres2) / tot2, 1)),
             file.path(dirb, "modelo_multinivel_var_part.csv"), sep = ";", bom = TRUE)
      co2 <- summary(m2)$coefficients
      if ("pobreza10" %in% rownames(co2)) {
        or2 <- exp(co2["pobreza10", "Estimate"])
        lo2 <- exp(co2["pobreza10", "Estimate"] - 1.96 * co2["pobreza10", "Std. Error"])
        hi2 <- exp(co2["pobreza10", "Estimate"] + 1.96 * co2["pobreza10", "Std. Error"])
        fwrite(data.table(indicador = c("OR_pobreza_x10pp", "IC95_inferior",
                                        "IC95_superior", "p_valor"),
                          valor = round(c(or2, lo2, hi2, co2["pobreza10", "Pr(>|z|)"]), 4)),
               file.path(dirb, "modelo_determinantes_part.csv"), sep = ";", bom = TRUE)
      }
      .estado(dirb, "multinivel_part", "ok",
              sprintf("universo participativo (n=%d estab): var estab %.1f%% comuna %.1f%%",
                      d2[, uniqueN(IdEstablecimiento)], 100 * ve2 / tot2, 100 * vco2 / tot2))
    }
  }

  # Cobertura comunal vs pobreza (insumo del mapa y del espacial).
  estab_part <- unique(part[bloque == blq]$IdEstablecimiento)
  e <- copy(est); e[, participa := IdEstablecimiento %in% estab_part]
  cob_com <- e[, .(cobertura = round(100 * mean(participa), 1), n = .N), by = IdComuna]
  cob_com <- merge(cob_com, com[, .(IdComuna, comuna, pct_pobreza, poblacion)],
                   by = "IdComuna")
  fwrite(cob_com, file.path(dirb, "cobertura_vs_pobreza.csv"), sep = ";", bom = TRUE)
  .estado(dirb, "multinivel", "ok",
          sprintf("var estab %.1f%% comuna %.1f%% region %.1f%%",
                  100 * v_est / tot, 100 * v_com / tot, 100 * v_reg / tot))
  invisible(TRUE)
}

# ---- 9. Autocorrelación espacial: I de Moran + LISA ------------------------
espacial_bloque <- function(blq, dirb) {
  pkgs <- c("sf", "spdep", "chilemapas")
  if (!all(vapply(pkgs, requireNamespace, logical(1), quietly = TRUE))) {
    .estado(dirb, "espacial", "omitido", "faltan paquetes sf/spdep/chilemapas")
    return(invisible(FALSE))
  }
  f_cob <- file.path(dirb, "cobertura_vs_pobreza.csv")
  if (!file.exists(f_cob)) {
    .estado(dirb, "espacial", "omitido", "falta cobertura_vs_pobreza.csv")
    return(invisible(FALSE))
  }
  suppressPackageStartupMessages({ library(sf); library(spdep) })
  cob <- fread(f_cob, sep = ";"); cob[, codigo_comuna := sprintf("%05d", IdComuna)]
  mapa <- sf::st_as_sf(chilemapas::mapa_comunas)
  mapa <- merge(mapa, cob[, .(codigo_comuna, cobertura)], by = "codigo_comuna", all.x = TRUE)
  mapa <- mapa[!is.na(mapa$cobertura), ]
  if (nrow(mapa) < 10) {
    .estado(dirb, "espacial", "omitido", "muy pocas comunas con dato")
    return(invisible(FALSE))
  }
  res <- tryCatch({
    nb <- spdep::poly2nb(mapa, queen = TRUE)
    lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
    mi <- spdep::moran.test(mapa$cobertura, lw, zero.policy = TRUE, na.action = na.omit)
    fwrite(data.table(indicador = c("I_Moran", "valor_esperado", "p_valor"),
      valor = round(c(mi$estimate[["Moran I statistic"]],
                      mi$estimate[["Expectation"]], mi$p.value), 4)),
      file.path(dirb, "moran_global.csv"), sep = ";", bom = TRUE)
    lm <- spdep::localmoran(mapa$cobertura, lw, zero.policy = TRUE)
    z <- scale(mapa$cobertura)[, 1]; lagz <- spdep::lag.listw(lw, z, zero.policy = TRUE)
    p <- lm[, "Pr(z != E(Ii))"]
    cl <- fifelse(p >= 0.05, "No significativo",
          fifelse(z > 0 & lagz > 0, "Alto-Alto (foco de participación)",
          fifelse(z < 0 & lagz < 0, "Bajo-Bajo (foco de subregistro)",
          fifelse(z > 0 & lagz < 0, "Alto-Bajo (atípico)", "Bajo-Alto (atípico)"))))
    fwrite(data.table(codigo_comuna = mapa$codigo_comuna, cobertura = mapa$cobertura,
                      lisa_cluster = cl), file.path(dirb, "lisa_comuna.csv"),
           sep = ";", bom = TRUE)
    .estado(dirb, "espacial", "ok",
            sprintf("I=%.3f p=%.3f", mi$estimate[["Moran I statistic"]], mi$p.value))
    TRUE
  }, error = function(e) { .estado(dirb, "espacial", "error", conditionMessage(e)); FALSE })
  invisible(res)
}

# ---- 9b. Descomposicion de varianza del establecimiento (gestion vs tipo) --
# Cuanto del efecto establecimiento explican tipo y nivel (M0 nulo -> M1 +tipo
# -> M2 +tipo+nivel). Lo que NO explican = variacion entre centros del mismo
# tipo/nivel (candidata a "gestion").
modelo_descomposicion <- function(panel, blq, dirb) {
  d <- copy(panel)[!is.na(tipo_grp) & !is.na(nivel_atencion)]
  if (d[, sum(reporta)] < 30) {
    .estado(dirb, "descomposicion", "omitido", "pocos positivos"); return(invisible(FALSE))
  }
  tiene_dep <- Sys.getenv("REM_DEP", unset = "0") == "1" &&
               "dependencia" %in% names(d) && d[, uniqueN(dependencia)] > 1
  d[, `:=`(tipo_grp = .factor_tipo(tipo_grp),
           nivel_atencion = factor(nivel_atencion),
           IdEstablecimiento = factor(IdEstablecimiento))]
  if (tiene_dep) d[, dependencia := factor(dependencia)]
  ctrl <- glmerControl(optimizer = "bobyqa", optCtrl = list(maxfun = 2e5))
  fit  <- function(f) tryCatch(glmer(f, family = binomial, data = d, nAGQ = .nagq(), control = ctrl),
                               error = function(e) NULL)
  vget <- function(m) if (is.null(m)) NA_real_ else as.numeric(VarCorr(m)$IdEstablecimiento)
  m0 <- fit(reporta ~ (1 | IdEstablecimiento))
  m1 <- fit(reporta ~ tipo_grp + (1 | IdEstablecimiento))
  m2 <- fit(reporta ~ tipo_grp + nivel_atencion + (1 | IdEstablecimiento))
  m3 <- if (tiene_dep)
    fit(reporta ~ tipo_grp + nivel_atencion + dependencia + (1 | IdEstablecimiento)) else NULL
  v0 <- vget(m0); v1 <- vget(m1); v2 <- vget(m2); v3 <- vget(m3)
  red <- function(v) if (!is.na(v0) && v0 > 0 && !is.na(v)) round(100 * (v0 - v) / v0, 1) else NA
  mods <- c("M0 nulo (solo establecimiento)", "M1 + tipo", "M2 + tipo + nivel")
  vars <- c(v0, v1, v2); reds <- c(0, red(v1), red(v2))
  if (!is.null(m3)) {
    mods <- c(mods, "M3 + tipo + nivel + dependencia")
    vars <- c(vars, v3); reds <- c(reds, red(v3))
  }
  tab <- data.table(modelo = mods, var_establecimiento = round(vars, 3),
                    pct_reduccion_vs_M0 = reds)
  fwrite(tab, file.path(dirb, "modelo_descomposicion.csv"), sep = ";", bom = TRUE)
  # OR de cada dependencia (vs referencia) en la barrera, condicional a tipo+nivel.
  if (!is.null(m3)) {
    co <- tryCatch(summary(m3)$coefficients, error = function(e) NULL)
    if (!is.null(co)) {
      rn <- rownames(co); idx <- grep("^dependencia", rn)
      if (length(idx))
        fwrite(data.table(
          dependencia = sub("^dependencia", "", rn[idx]),
          OR_vs_ref = round(exp(co[idx, "Estimate"]), 2),
          IC95_inf = round(exp(co[idx, "Estimate"] - 1.96 * co[idx, "Std. Error"]), 2),
          IC95_sup = round(exp(co[idx, "Estimate"] + 1.96 * co[idx, "Std. Error"]), 2),
          p_valor = round(co[idx, "Pr(>|z|)"], 4))[order(-OR_vs_ref)],
          file.path(dirb, "modelo_dependencia_or.csv"), sep = ";", bom = TRUE)
    }
  }
  .estado(dirb, "descomposicion", "ok",
          sprintf("tipo+nivel explican %s%% del efecto establecimiento%s",
                  ifelse(is.na(red(v2)), "NA", red(v2)),
                  if (!is.na(v3)) sprintf("; +dependencia %s%%", red(v3)) else ""))
  invisible(TRUE)
}

# ---- 9c. Efecto red: el patron espacial es la red (Servicio de Salud)? -----
# Compara el I de Moran de la cobertura comunal con el I de Moran de los
# RESIDUOS tras descontar la media de cada Servicio de Salud. Si el patron
# espacial cae a ~0, "lo que parece territorio" es la red de gestion.
red_servicio <- function(est, blq, dirb) {
  pkgs <- c("sf", "spdep", "chilemapas")
  if (!all(vapply(pkgs, requireNamespace, logical(1), quietly = TRUE))) {
    .estado(dirb, "red_servicio", "omitido", "faltan paquetes"); return(invisible(FALSE))
  }
  f_cob <- file.path(dirb, "cobertura_vs_pobreza.csv")
  if (!file.exists(f_cob) || !("servicio_salud" %in% names(est))) {
    .estado(dirb, "red_servicio", "omitido", "falta cobertura o servicio_salud")
    return(invisible(FALSE))
  }
  res <- tryCatch({
    suppressPackageStartupMessages({ library(sf); library(spdep) })
    cob <- fread(f_cob, sep = ";")
    cs <- est[!is.na(servicio_salud), .N, by = .(IdComuna, servicio_salud)][order(-N)]
    cs <- cs[, .SD[1], by = IdComuna][, .(IdComuna, servicio_salud)]
    cob <- merge(cob, cs, by = "IdComuna", all.x = TRUE)[!is.na(servicio_salud)]
    serv <- cob[, .(cobertura = round(sum(cobertura * n) / sum(n), 1),
                    n_comunas = .N, n_estab = sum(n)), by = servicio_salud][order(-cobertura)]
    fwrite(serv, file.path(dirb, "cobertura_servicio_red.csv"), sep = ";", bom = TRUE)
    cob[, cob_serv := sum(cobertura * n) / sum(n), by = servicio_salud]
    cob[, residual := cobertura - cob_serv]
    cob[, codigo_comuna := sprintf("%05d", IdComuna)]
    mapa <- sf::st_as_sf(chilemapas::mapa_comunas)
    mapa <- merge(mapa, cob[, .(codigo_comuna, cobertura, residual)],
                  by = "codigo_comuna", all.x = TRUE)
    mapa <- mapa[!is.na(mapa$cobertura) & !is.na(mapa$residual), ]
    nb <- spdep::poly2nb(mapa, queen = TRUE)
    lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
    mi_raw <- spdep::moran.test(mapa$cobertura, lw, zero.policy = TRUE, na.action = na.omit)
    mi_res <- spdep::moran.test(mapa$residual,  lw, zero.policy = TRUE, na.action = na.omit)
    fwrite(data.table(
      indicador = c("I_Moran_comuna", "p_comuna",
                    "I_Moran_residual_servicio", "p_residual"),
      valor = round(c(mi_raw$estimate[["Moran I statistic"]], mi_raw$p.value,
                      mi_res$estimate[["Moran I statistic"]], mi_res$p.value), 4)),
      file.path(dirb, "moran_servicio.csv"), sep = ";", bom = TRUE)
    .estado(dirb, "red_servicio", "ok",
            sprintf("Moran comuna %.3f -> residual servicio %.3f",
                    mi_raw$estimate[["Moran I statistic"]],
                    mi_res$estimate[["Moran I statistic"]]))
    TRUE
  }, error = function(e) { .estado(dirb, "red_servicio", "error", conditionMessage(e)); FALSE })
  invisible(res)
}

# ---- 10. Tipologías k-means (composición interna del bloque) ---------------
# Agrupa establecimientos por la COMPOSICIÓN de su actividad dentro del bloque:
#   A -> familias de reclamo · B -> instancias (B.1) · C -> líneas (C.1).
tipologias_bloque <- function(part, largo, est, blq, dirb, k = 4) {
  comp <- NULL
  if (blq == "A") {
    pb <- part[bloque == "A" & valor_total > 0]
    comp <- pb[, .(v = sum(valor_total, na.rm = TRUE)),
               by = .(IdEstablecimiento, cat = familia_reclamo(descripcion))]
  } else if (blq == "B") {
    lg <- largo[seccion_key == "B.1" & dimension == "instancia" & valor > 0]
    comp <- lg[, .(v = sum(valor, na.rm = TRUE)), by = .(IdEstablecimiento, cat = etiqueta)]
  } else if (blq == "C") {
    lg <- largo[seccion_key == "C.1" &
                dimension %in% c("linea_satisfaccion", "instancia") & valor > 0]
    comp <- lg[, .(v = sum(valor, na.rm = TRUE)), by = .(IdEstablecimiento, cat = etiqueta)]
  }
  if (is.null(comp) || comp[, uniqueN(IdEstablecimiento)] < (k * 5) ||
      comp[, uniqueN(cat)] < 2) {
    .estado(dirb, "tipologias", "omitido", "datos insuficientes para k-means")
    return(invisible(FALSE))
  }
  w <- dcast(comp, IdEstablecimiento ~ cat, value.var = "v", fill = 0)
  cats <- setdiff(names(w), "IdEstablecimiento")
  M <- as.matrix(w[, ..cats]); M <- M / pmax(rowSums(M), 1)   # shares por establecimiento
  S <- as.data.table(M); S[, IdEstablecimiento := w$IdEstablecimiento]
  # Transformacion clr (centered log-ratio) para datos composicionales (Aitchison
  # 1986): pseudoconteo para ceros, log y centrado por fila. Respeta la geometria
  # del simplex, a diferencia de la distancia euclidiana sobre shares crudas.
  L <- log(M + 1e-6); clr <- L - rowMeans(L)
  res <- tryCatch({
    set.seed(123)
    Z <- clr; Z[!is.finite(Z)] <- 0
    # Silueta media para k=2..6: justifica el k elegido (diagnostico, muestreado).
    if (requireNamespace("cluster", quietly = TRUE)) {
      idx <- if (nrow(Z) > 600) sample(nrow(Z), 600) else seq_len(nrow(Z))
      Zs <- Z[idx, , drop = FALSE]; ds <- dist(Zs)
      sil <- sapply(2:6, function(kk)
        mean(cluster::silhouette(kmeans(Zs, centers = kk, nstart = 10)$cluster, ds)[, 3]))
      fwrite(data.table(k = 2:6, silueta_media = round(sil, 3)),
             file.path(dirb, "tipologias_silueta.csv"), sep = ";", bom = TRUE)
    }
    km <- kmeans(Z, centers = k, nstart = 25)
    S[, perfil := km$cluster]
    perfil <- S[, c(list(n_establecimientos = .N),
                    lapply(.SD, function(x) round(100 * mean(x), 1))),
                by = perfil, .SDcols = cats][order(perfil)]
    fwrite(perfil, file.path(dirb, "tipologias_perfil.csv"), sep = ";", bom = TRUE)
    asign <- merge(S[, .(IdEstablecimiento, perfil)],
                   est[, .(IdEstablecimiento, TipoEstablecimientoGlosa, IdRegion)],
                   by = "IdEstablecimiento", all.x = TRUE)
    fwrite(asign, file.path(dirb, "tipologias_asignacion.csv"), sep = ";", bom = TRUE)
    .estado(dirb, "tipologias", "ok", sprintf("k=%d sobre %d establecimientos", k, nrow(w)))
    TRUE
  }, error = function(e) { .estado(dirb, "tipologias", "error", conditionMessage(e)); FALSE })
  invisible(res)
}
