# =============================================================================
# 11_monitoreo_2026.R  ·  Monitoreo del ano en curso (REM preliminar)
# -----------------------------------------------------------------------------
# Trata el ano preliminar (2026) como MONITOREO, no como ano cerrado:
#   1. Detecta el corte de meses disponibles.
#   2. Mide cobertura/subregistro/eventos SOLO sobre los meses transcurridos.
#   3. Compara el MISMO periodo contra el ano de referencia (2025).
#   4. Proyecta el cierre con perfil estacional del ano de referencia y una
#      banda por escenarios de rezago de reporte.
#   5. Diagnostico de rezago (estab y eventos por mes) para ver el corte real.
#
# Es STANDALONE: lee los .rds ya procesados de cada ano (no toca 01 ni 04).
# Requisito: haber corrido 00 y 01 para AMBOS anos. Para el 2026:
#   Sys.setenv(REM_ANIO = "2026"); source("R/00_descarga.R"); source("R/01_procesamiento.R")
# Luego:  source("R/11_monitoreo_2026.R")
#
# Supuestos (declarados): el ano de referencia esta completo (12 meses) y la
# estacionalidad de cada bloque es estable entre anos. Toda salida es PRELIMINAR.
# =============================================================================
suppressPackageStartupMessages({ library(here); library(data.table) })

anio_ref <- as.integer(Sys.getenv("REM_ANIO_REF", unset = "2025"))
anio_mon <- as.integer(Sys.getenv("REM_ANIO",     unset = "2026"))

# El monitoreo aplica al ano PRELIMINAR (posterior al de referencia). Si se corre
# para un ano que no es posterior (p. ej. dentro de run_all del ano de referencia),
# se omite limpio (run_all lo captura y sigue).
if (anio_mon <= anio_ref)
  stop("monitoreo: el ano monitoreado (", anio_mon, ") no es posterior al de referencia (",
       anio_ref, "); no aplica.")

leer <- function(a, f) {
  p <- here("datos", as.character(a), f)
  if (file.exists(p)) readRDS(p) else NULL
}
part_ref <- leer(anio_ref, "participacion_A19b.rds")
part_mon <- leer(anio_mon, "participacion_A19b.rds")
uni_ref  <- leer(anio_ref, "universo_estab_mes.rds")
uni_mon  <- leer(anio_mon, "universo_estab_mes.rds")

if (is.null(part_mon) || is.null(uni_mon))
  stop("Falta procesar el ano ", anio_mon,
       ". Corre 00 y 01 con Sys.setenv(REM_ANIO='", anio_mon, "') primero.")
if (is.null(part_ref) || is.null(uni_ref))
  stop("Falta el ano de referencia ", anio_ref,
       " procesado (datos/", anio_ref, "/participacion_A19b.rds).")

for (x in list(part_ref, part_mon, uni_ref, uni_mon)) setDT(x)
dir_out <- here("productos", paste0("monitoreo_", anio_mon))
dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

# ---- 1. Corte de meses disponibles en el ano monitoreado -------------------
corte <- max(uni_mon$Mes, na.rm = TRUE)
fwrite(data.table(ano = anio_mon, ultimo_mes = corte,
                  n_meses = uniqueN(uni_mon$Mes),
                  fecha_proceso = as.character(Sys.Date())),
       file.path(dir_out, "corte.csv"), sep = ";", bom = TRUE)
message("Corte de meses ", anio_mon, ": ", corte, " (", uniqueN(uni_mon$Mes), " meses con dato).")

# ---- 2. Diagnostico de rezago: estab y eventos por mes ---------------------
# Si el ultimo mes cae notoriamente, hay rezago de reporte (no menos actividad).
diag <- merge(
  uni_mon[, .(estab_activos = uniqueN(IdEstablecimiento)), by = Mes],
  part_mon[, .(eventos = sum(valor_total, na.rm = TRUE)), by = Mes],
  by = "Mes", all = TRUE)[order(Mes)]
fwrite(diag, file.path(dir_out, "diag_meses.csv"), sep = ";", bom = TRUE)

# ---- 3. Metricas del mismo periodo (1..corte) por bloque -------------------
kpi_periodo <- function(part, uni, blq, hasta) {
  u  <- uni[Mes <= hasta]
  activos <- uniqueN(u$IdEstablecimiento)
  pb <- part[bloque == blq & Mes <= hasta]
  participa <- uniqueN(pb[valor_total > 0]$IdEstablecimiento)
  pan <- merge(u[, .(IdEstablecimiento, Mes)],
               pb[, .(v = sum(valor_total, na.rm = TRUE)), by = .(IdEstablecimiento, Mes)],
               by = c("IdEstablecimiento", "Mes"), all.x = TRUE)
  pan[is.na(v), v := 0]
  data.table(bloque = blq, estab_activos = activos, estab_participa = participa,
             cobertura_pct = round(100 * participa / max(activos, 1), 1),
             eventos = sum(pb$valor_total, na.rm = TRUE),
             subregistro_pct = round(100 * mean(pan$v == 0), 1))
}

comp <- rbindlist(lapply(c("A", "B", "C"), function(b) {
  r <- kpi_periodo(part_ref, uni_ref, b, corte); r[, ano := anio_ref]
  m <- kpi_periodo(part_mon, uni_mon, b, corte); m[, ano := anio_mon]
  rbind(r, m)
}))
setcolorder(comp, "ano")
fwrite(comp[order(bloque, ano)],
       file.path(dir_out, "comparacion_periodo.csv"), sep = ";", bom = TRUE)

# Variacion del mismo periodo (mon vs ref), en cobertura y eventos.
var <- dcast(comp, bloque ~ ano, value.var = c("cobertura_pct", "eventos"))
setnames(var, names(var), gsub("_(\\d+)$", "_\\1", names(var)))
cob_ref <- paste0("cobertura_pct_", anio_ref); cob_mon <- paste0("cobertura_pct_", anio_mon)
ev_ref  <- paste0("eventos_", anio_ref);       ev_mon  <- paste0("eventos_", anio_mon)
var[, dif_cobertura_pp := round(get(cob_mon) - get(cob_ref), 1)]
var[, var_eventos_pct  := round(100 * (get(ev_mon) - get(ev_ref)) / pmax(get(ev_ref), 1), 1)]
fwrite(var, file.path(dir_out, "variacion_periodo.csv"), sep = ";", bom = TRUE)

# ---- 4. Proyeccion de cierre con perfil estacional + banda de rezago -------
# Share mensual de cada bloque en el ano de referencia (completo).
share_ref <- part_ref[bloque %in% c("A", "B", "C"),
                      .(ev = sum(valor_total, na.rm = TRUE)), by = .(bloque, Mes)]
share_ref[, share := ev / sum(ev), by = bloque]
Sacum <- share_ref[Mes <= corte, .(S = sum(share)), by = bloque]   # share acumulado a corte

ev_mon <- part_mon[bloque %in% c("A", "B", "C") & Mes <= corte,
                   .(ev_acum = sum(valor_total, na.rm = TRUE)), by = bloque]
u2 <- part_mon[bloque %in% c("A", "B", "C") & Mes %in% c(corte - 1L, corte),
               .(ev_u2 = sum(valor_total, na.rm = TRUE)), by = bloque]

proj <- Reduce(function(a, b) merge(a, b, by = "bloque", all.x = TRUE),
               list(ev_mon, Sacum, u2))
proj[is.na(ev_u2), ev_u2 := 0]
escenario <- function(f) round((proj$ev_acum + f * proj$ev_u2) / pmax(proj$S, 1e-9))
proj[, `:=`(
  acumulado_observado = ev_acum,
  share_acumulado_ref = round(S, 3),
  proyeccion_base = escenario(0),          # sin correccion de rezago
  proyeccion_rezago_15 = escenario(0.15),  # ultimos 2 meses suben 15%
  proyeccion_rezago_30 = escenario(0.30))] # ultimos 2 meses suben 30%
fwrite(proj[, .(bloque, acumulado_observado, share_acumulado_ref,
                proyeccion_base, proyeccion_rezago_15, proyeccion_rezago_30)],
       file.path(dir_out, "proyeccion_cierre.csv"), sep = ";", bom = TRUE)

# ---- 5. Trayectoria multianual: incorporar el ano previo (solo A y B) ------
# El ano previo (por defecto, anio_ref - 1) tiene MENOS detalle: solo bloques A y B
# y un subconjunto de codigos. Para que sea comparable, todo lo multianual se hace
# sobre los CODIGOS COMUNES a ambos anos. Da una segunda referencia estacional y una
# senal de tendencia interanual. Degrada si el ano previo no esta procesado.
anio_prev <- as.integer(Sys.getenv("REM_ANIO_PREV", unset = as.character(anio_ref - 1L)))
part_prev <- leer(anio_prev, "participacion_A19b.rds")
if (!is.null(part_prev)) {
  setDT(part_prev)
  filas <- list()
  for (blq in c("A", "B")) {
    comun <- intersect(unique(part_prev[bloque == blq, CodigoPrestacion]),
                       unique(part_ref [bloque == blq, CodigoPrestacion]))
    if (length(comun) == 0) next
    sm <- function(pp) {
      d <- pp[bloque == blq & CodigoPrestacion %chin% comun,
              .(ev = sum(valor_total, na.rm = TRUE)), by = Mes]
      d[, share := ev / max(sum(ev), 1)]; d[, .(Mes, share)]
    }
    sp <- sm(part_prev); setnames(sp, "share", "s_prev")
    sr <- sm(part_ref);  setnames(sr, "share", "s_ref")
    sa <- merge(sp, sr, by = "Mes", all = TRUE)
    sa[is.na(s_prev), s_prev := 0]; sa[is.na(s_ref), s_ref := 0]
    sa[, share := (s_prev + s_ref) / 2]
    S_corte <- sa[Mes <= corte, sum(share)]
    ev_prev <- part_prev[bloque == blq & CodigoPrestacion %chin% comun, sum(valor_total, na.rm = TRUE)]
    ev_refy <- part_ref [bloque == blq & CodigoPrestacion %chin% comun, sum(valor_total, na.rm = TRUE)]
    ev_monc <- part_mon [bloque == blq & CodigoPrestacion %chin% comun & Mes <= corte,
                         sum(valor_total, na.rm = TRUE)]
    filas[[blq]] <- data.table(
      bloque = blq, n_codigos_comunes = length(comun),
      eventos_prev = ev_prev, eventos_ref = ev_refy,
      var_interanual_pct = round(100 * (ev_refy - ev_prev) / max(ev_prev, 1), 1),
      acumulado_mon_comun = ev_monc,
      proyeccion_mon_comun = round(ev_monc / max(S_corte, 1e-9)))
  }
  if (length(filas)) {
    ten <- rbindlist(filas)
    setnames(ten, c("eventos_prev", "eventos_ref"),
             c(paste0("eventos_", anio_prev), paste0("eventos_", anio_ref)))
    fwrite(ten, file.path(dir_out, "tendencia_multianual.csv"), sep = ";", bom = TRUE)
    message("Trayectoria multianual (", anio_prev, " y ", anio_ref,
            ", codigos comunes, bloques A y B) en tendencia_multianual.csv.")
  }
} else {
  message("Ano previo ", anio_prev, " no procesado; se omite la vista multianual ",
          "(corre 00 y 01 con REM_ANIO=", anio_prev, " para incluirlo).")
}

message("Monitoreo ", anio_mon, " escrito en productos/monitoreo_", anio_mon, "/ ",
        "(corte.csv, diag_meses.csv, comparacion_periodo.csv, variacion_periodo.csv, proyeccion_cierre.csv).")
message("REVISA diag_meses.csv: si el ultimo mes cae mucho, el rezago es fuerte y la proyeccion realista esta entre _rezago_15 y _rezago_30.")
