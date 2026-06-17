# =============================================================================
# 12_a06_salud_mental.R  ·  Analisis complementario: A06 C.1 (coordinacion
#   comunitaria en salud mental) y su relacion con la participacion A19b.
# -----------------------------------------------------------------------------
# NO redefine el constructo de participacion (A19b). Estudia el SOLAPE entre dos
# registros: el A06 revela participacion comunitaria que el A19b no captura?
# Distingue, segun la literatura (ver EVALUACION_A06.md), participacion
# comunitaria (organizaciones de base, usuarios/familiares, autoayuda) de
# coordinacion intersectorial. Lee Serie A cruda + diccionario; construye sus
# propios insumos (no toca el crosswalk ni el lookup compartidos).
#
# Uso (consola de R):  source("R/12_a06_salud_mental.R")
# =============================================================================
suppressPackageStartupMessages({ library(here); library(readxl); library(data.table) })
anio <- as.integer(Sys.getenv("REM_ANIO", unset = "2025"))
dir_out <- here("productos", "a06"); dir.create(dir_out, recursive = TRUE, showWarnings = FALSE)

# ---- 1. Crosswalk A06 C.1 desde el diccionario -----------------------------
dicc <- list.files(here("Diccionarios"),
  pattern = sprintf("SA_%02d.*[.]xlsm$", anio %% 100), full.names = TRUE)[1]
if (is.na(dicc)) dicc <- here("Diccionarios", "DICCIONARIO CODIGOS SA_25_V1.5.xlsm")
crudo <- as.data.table(read_excel(dicc, sheet = "A06", col_names = FALSE, col_types = "text"))
colA <- crudo[[1]]; colB <- crudo[[2]]
seccion <- NA_character_; filas <- list()
for (i in seq_len(nrow(crudo))) {
  a <- trimws(ifelse(is.na(colA[i]), "", colA[i]))
  b <- trimws(ifelse(is.na(colB[i]), "", colB[i]))
  if (grepl("^SECC", b, ignore.case = TRUE)) { seccion <- b; next }
  if (grepl("^[0-9]{8}$", a) && grepl("C\\.?1\\b", seccion) &&
      grepl("COORDINAC", seccion, ignore.case = TRUE) && nzchar(b))
    filas[[length(filas) + 1]] <- data.table(codigo = a, descripcion = b)
}
cw <- unique(rbindlist(filas), by = "codigo")
cw[, clase := fifelse(
  grepl("comunitari|usuarios y familiares|autoayuda", descripcion, ignore.case = TRUE),
  "Participacion comunitaria", "Coordinacion intersectorial")]
fwrite(cw, file.path(dir_out, "crosswalk_a06_c1.csv"), sep = ";", bom = TRUE)
if (nrow(cw) == 0) stop("No se encontraron codigos de A06 C.1; revisar el diccionario.")
message("A06 C.1: ", nrow(cw), " codigos (",
        cw[clase == "Participacion comunitaria", .N], " comunitarios, ",
        cw[clase == "Coordinacion intersectorial", .N], " intersectoriales).")

# ---- 2. Serie A: actividad A06 C.1 por establecimiento ---------------------
ruta_serieA <- list.files(here("datos", as.character(anio)),
  pattern = sprintf("SerieA%d\\.csv$", anio), full.names = TRUE, recursive = TRUE)[1]
serieA <- fread(ruta_serieA, sep = ";", encoding = "UTF-8",
                select = c("IdEstablecimiento", "CodigoPrestacion", "IdRegion", "Mes", "Col01"),
                colClasses = list(character = "CodigoPrestacion"))
# Region por establecimiento (constante en la Serie A): denominador del semaforo.
estab_region <- unique(
  serieA[, .(cod = as.character(IdEstablecimiento),
             IdRegion = suppressWarnings(as.integer(IdRegion)))], by = "cod")
a06 <- merge(serieA[CodigoPrestacion %chin% cw$codigo], cw,
             by.x = "CodigoPrestacion", by.y = "codigo", all.x = TRUE)
a06[, val := suppressWarnings(as.numeric(Col01))]
# Serie mensual de la participacion comunitaria (insumo de la pagina D).
serie_a06 <- a06[clase == "Participacion comunitaria" & !is.na(val) & val > 0,
                 .(eventos = sum(val), establecimientos = uniqueN(IdEstablecimiento)),
                 by = .(Mes = suppressWarnings(as.integer(Mes)))][order(Mes)]
fwrite(serie_a06, file.path(dir_out, "serie_a06.csv"), sep = ";", bom = TRUE)
rm(serieA); gc()
estab_com <- unique(a06[clase == "Participacion comunitaria" & !is.na(val) & val > 0, IdEstablecimiento])
estab_a06 <- unique(a06[!is.na(val) & val > 0, IdEstablecimiento])

# ---- 3. Participacion A19b por establecimiento -----------------------------
part <- readRDS(here("datos", as.character(anio), "participacion_A19b.rds")); setDT(part)
estab_b <- unique(part[bloque == "B" & valor_total > 0, IdEstablecimiento])

# ---- 4. Universo y tipo de establecimiento (desde la maestra) --------------
uni <- readRDS(here("datos", as.character(anio), "universo_estab_mes.rds")); setDT(uni)
maestra <- fread(here("datos", "establecimientos_maestra.csv"), sep = ";", encoding = "UTF-8",
  select = c("EstablecimientoCodigo", "EstablecimientoCodigoAntiguo", "TipoEstablecimientoGlosa"),
  colClasses = "character")
l1 <- maestra[EstablecimientoCodigo != "", .(cod = EstablecimientoCodigo, tipo = TipoEstablecimientoGlosa)]
l2 <- maestra[!is.na(EstablecimientoCodigoAntiguo) & EstablecimientoCodigoAntiguo != "",
              .(cod = EstablecimientoCodigoAntiguo, tipo = TipoEstablecimientoGlosa)]
lookup <- unique(rbindlist(list(l1, l2)), by = "cod")
d <- data.table(IdEstablecimiento = unique(uni$IdEstablecimiento))
d[, cod := as.character(IdEstablecimiento)]
d <- merge(d, lookup, by = "cod", all.x = TRUE)
d[is.na(tipo) | tipo == "", tipo := "Sin dato"]
d[, `:=`(a06_com = IdEstablecimiento %in% estab_com,
         a06_any = IdEstablecimiento %in% estab_a06,
         a19_B   = IdEstablecimiento %in% estab_b)]
# Cobertura comunitaria por region (mismo universo d): columna D del semaforo.
d <- merge(d, estab_region, by = "cod", all.x = TRUE)
cob_reg_a06 <- d[!is.na(IdRegion),
                 .(n = .N, pct = round(100 * mean(a06_com), 1)),
                 by = IdRegion][order(IdRegion)]
fwrite(cob_reg_a06, file.path(dir_out, "cobertura_region_a06.csv"), sep = ";", bom = TRUE)

# ---- 5. Productos ----------------------------------------------------------
fwrite(data.table(
  indicador = c("establecimientos_activos", "cobertura_a06_c1_comunitaria_pct",
                "cobertura_a06_c1_total_pct", "cobertura_a19b_B_pct"),
  valor = c(nrow(d), round(100 * mean(d$a06_com), 1),
            round(100 * mean(d$a06_any), 1), round(100 * mean(d$a19_B), 1))),
  file.path(dir_out, "kpis_a06.csv"), sep = ";", bom = TRUE)

fwrite(d[, .N, by = .(a19_B, a06_com)][order(-a19_B, -a06_com)],
       file.path(dir_out, "solape_a19b_a06.csv"), sep = ";", bom = TRUE)

no_b <- d[a19_B == FALSE]
fwrite(data.table(
  indicador = c("estab_sin_participacion_social_A19b", "de_ellos_con_A06_comunitaria", "pct_revela"),
  valor = c(nrow(no_b), sum(no_b$a06_com), round(100 * mean(no_b$a06_com), 1))),
  file.path(dir_out, "revela.csv"), sep = ";", bom = TRUE)

fwrite(d[, .(n = .N, cob_a06_com_pct = round(100 * mean(a06_com), 1),
             cob_a19_B_pct = round(100 * mean(a19_B), 1)), by = tipo][order(-n)],
       file.path(dir_out, "cobertura_por_tipo.csv"), sep = ";", bom = TRUE)

# Desglose por clase: participacion comunitaria vs coordinacion intersectorial.
clase_tab <- a06[!is.na(val) & val > 0,
                 .(establecimientos = uniqueN(IdEstablecimiento), participantes = sum(val)),
                 by = clase][order(-establecimientos)]
fwrite(clase_tab, file.path(dir_out, "clase_a06.csv"), sep = ";", bom = TRUE)

message("A06 complementario escrito en productos/a06/.")
message(sprintf("REVELA: de %d establecimientos SIN participacion social A19b, %d (%.1f%%) si hacen trabajo comunitario A06 C.1.",
                nrow(no_b), sum(no_b$a06_com), 100 * mean(no_b$a06_com)))
