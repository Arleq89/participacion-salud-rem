# =============================================================================
# 01_procesamiento.R  ·  Limpieza y construccion de los datasets analiticos
# -----------------------------------------------------------------------------
# A partir de los datos crudos descargados, produce:
#   - crosswalk/crosswalk_participacion_A19b.csv : codigo -> prestacion -> bloque
#   - datos/<ANO>/participacion_A19b.rds          : Serie A filtrada a A19b
#   - datos/<ANO>/participacion_largo.rds         : formato largo etiquetado
#   - datos/<ANO>/universo_estab_mes.rds          : panel establecimiento x mes
#   - datos/establecimientos_lookup.rds           : atributos por establecimiento
#
# NUEVO (reformulacion por seccion): cada fila lleva ahora una columna `bloque`
# (A, B o C) y `seccion_key` (A, B.1, B.2, C.1, C.2). El analisis se hace por
# BLOQUE tematico: A = OIRS, B = participacion social (B.1+B.2),
# C = satisfaccion usuaria (C.1+C.2). Los layouts de columnas Col01..Col50
# difieren por seccion y se etiquetan con crosswalk/crosswalk_columnas_A19b.csv.
# =============================================================================
library(here)
library(readxl)
library(data.table)
anio <- as.integer(Sys.getenv("REM_ANIO", unset = "2025"))

# ---- 1. Crosswalk de prestaciones (desde el diccionario A19b) ---------------
# Diccionario A19b del ano correspondiente. OJO: el instrumento 2024 registra
# MENOS detalle que 2025 (menos prestaciones y columnas); las comparaciones finas
# entre anos (subsecciones, equidad) no son del todo comparables, solo el nivel de
# bloque (cobertura, eventos). El crosswalk de columnas es curado de 2025.
ruta_dicc <- list.files(here("Diccionarios"),
  pattern = sprintf("SA_%02d.*[.]xlsm$", anio %% 100), full.names = TRUE)[1]
if (is.na(ruta_dicc))
  ruta_dicc <- here("Diccionarios", "DICCIONARIO CODIGOS SA_25_V1.5.xlsm")
message("Diccionario A19b: ", basename(ruta_dicc))
crudo <- as.data.table(read_excel(ruta_dicc, sheet = "A19b",
                                  col_names = FALSE, col_types = "text"))
colA <- crudo[[1]]; colB <- crudo[[2]]
seccion <- NA_character_; en_elim <- FALSE; filas <- list()
for (i in seq_len(nrow(crudo))) {
  a <- trimws(ifelse(is.na(colA[i]), "", colA[i]))
  b <- trimws(ifelse(is.na(colB[i]), "", colB[i]))
  if (grepl("^C[OO]DIGOS ELIMINADOS", a, ignore.case = TRUE)) { en_elim <- TRUE; next }
  if (grepl("^C[OO]DIGOS NUEVOS",    a, ignore.case = TRUE)) { en_elim <- FALSE; next }
  # Encabezados de seccion. Solo las secciones-hoja (A, B.1, B.2, C.1, C.2)
  # tienen prestaciones; "SECCION B" y "SECCION C" son encabezados paraguas.
  if (grepl("^SECC", b, ignore.case = TRUE)) { seccion <- b; next }
  if (grepl("^[0-9]{8}$", a) && !en_elim && !(b %in% c("", "0")))
    filas[[length(filas) + 1]] <- data.table(codigo = a, descripcion = b, seccion = seccion)
}
crosswalk <- unique(rbindlist(filas), by = "codigo")

# seccion_key: A, B.1, B.2, C.1, C.2  ·  bloque: A, B, C  ·  tema legible
# (patron robusto: "SECCION <key>:" -> <key>, sin depender de los acentos)
crosswalk[, seccion_key := sub("^[^ ]+ ([A-Z](\\.[0-9])?):.*$", "\\1", seccion)]
crosswalk[, bloque := substr(seccion_key, 1, 1)]
crosswalk[, tema := fcase(
  bloque == "A", "OIRS / Reclamos y solicitudes",
  bloque == "B", "Participacion social",
  bloque == "C", "Satisfaccion usuaria y humanizacion",
  default = "Otra")]
crosswalk[, `:=`(serie = "A", seccion_rem = "A19b")]
setcolorder(crosswalk, c("codigo", "descripcion", "bloque", "seccion_key",
                         "tema", "seccion", "serie", "seccion_rem"))
dir.create(here("crosswalk"), showWarnings = FALSE)
fwrite(crosswalk, here("crosswalk", "crosswalk_participacion_A19b.csv"),
       sep = ";", bom = TRUE)
message("Crosswalk de prestaciones: ", nrow(crosswalk), " codigos activos.")
print(crosswalk[, .N, by = .(bloque, seccion_key)][order(bloque, seccion_key)])

# ---- 2. Leer la Serie A UNA sola vez ---------------------------------------
# (CSV ~738 MB) y derivar de ahi tanto la participacion filtrada como el
# universo establecimiento x mes que necesitan los modelos de panel.
ruta_serieA <- list.files(here("datos", as.character(anio)),
                          pattern = sprintf("SerieA%d\\.csv$", anio),
                          full.names = TRUE, recursive = TRUE)[1]
if (is.na(ruta_serieA)) stop("No se encontro SerieA", anio, ".csv en datos/", anio)
serieA <- fread(ruta_serieA, sep = ";", encoding = "UTF-8",
                colClasses = list(character = "CodigoPrestacion"))

# Universo establecimiento x mes (todos los que reportan ALGO en la Serie A).
universo <- unique(serieA[, .(IdEstablecimiento, Mes, IdRegion, IdComuna)],
                   by = c("IdEstablecimiento", "Mes"))
saveRDS(universo, here("datos", as.character(anio), "universo_estab_mes.rds"))
message("Universo establecimiento x mes: ",
        format(nrow(universo), big.mark = "."), " filas.")

# Participacion A19b.
part <- serieA[CodigoPrestacion %chin% crosswalk$codigo]
rm(serieA); gc()
part <- merge(part, crosswalk[, .(codigo, descripcion, tema, bloque, seccion, seccion_key)],
              by.x = "CodigoPrestacion", by.y = "codigo", all.x = TRUE, sort = FALSE)
setnames(part, "Col01", "valor_total")
part[, reporto := !is.na(valor_total)]
part[, es_cero := (!is.na(valor_total) & valor_total == 0)]
part[, fecha := as.Date(sprintf("%d-%02d-01", Ano, Mes))]
saveRDS(part, here("datos", as.character(anio), "participacion_A19b.rds"))
message("Participacion A19b: ", format(nrow(part), big.mark = "."), " filas.")

# ---- 3. Formato largo etiquetado (desagregaciones Col01..Col50) ------------
cw_col <- fread(here("crosswalk", "crosswalk_columnas_A19b.csv"),
                sep = ";", encoding = "UTF-8")
part[, Col01 := valor_total]
cols_valor <- sprintf("Col%02d", 1:50)
part[, (cols_valor) := lapply(.SD, as.numeric), .SDcols = cols_valor]
largo <- melt(part,
  id.vars = c("IdEstablecimiento", "Mes", "IdRegion", "IdComuna",
              "CodigoPrestacion", "tema", "bloque", "seccion_key", "descripcion"),
  measure.vars = cols_valor, variable.name = "col", value.name = "valor")
largo <- largo[!is.na(valor)]
largo[, col := as.character(col)]
largo <- merge(largo, cw_col, by = c("seccion_key", "col"), all.x = TRUE, sort = FALSE)
saveRDS(largo, here("datos", as.character(anio), "participacion_largo.rds"))
message("Tabla larga: ", format(nrow(largo), big.mark = "."), " filas.")

# ---- 4. Cruce con la base maestra de establecimientos ----------------------
attrs <- c("TipoEstablecimientoGlosa", "DependenciaAdministrativa",
           "NivelAtencionEstabglosa", "NivelComplejidadEstabGlosa",
           "TipoPertenenciaEstabGlosa", "ComunaGlosa", "RegionGlosa",
           "SeremiSaludGlosa_ServicioDeSaludGlosa",
           "Latitud", "Longitud", "EstadoFuncionamiento")
maestra <- fread(here("datos", "establecimientos_maestra.csv"), sep = ";",
                 encoding = "UTF-8",
                 select = c("EstablecimientoCodigo", "EstablecimientoCodigoAntiguo", attrs),
                 colClasses = "character")
l1 <- copy(maestra[EstablecimientoCodigo != ""]);            l1[, cod := EstablecimientoCodigo]
l2 <- copy(maestra[!is.na(EstablecimientoCodigoAntiguo) & EstablecimientoCodigoAntiguo != ""])
l2[, cod := EstablecimientoCodigoAntiguo]
lookup <- unique(rbindlist(list(l1, l2))[, c("cod", attrs), with = FALSE], by = "cod")

est <- unique(universo[, .(IdEstablecimiento, IdRegion, IdComuna)],
              by = "IdEstablecimiento")
est[, cod := as.character(IdEstablecimiento)]
est <- merge(est, lookup, by = "cod", all.x = TRUE, sort = FALSE)
saveRDS(est, here("datos", "establecimientos_lookup.rds"))
message("Establecimientos cruzados: ",
        round(100 * mean(!is.na(est$TipoEstablecimientoGlosa)), 1), "% match.")

# ---- 5. Validaciones del dato listo (aserciones que fallan ruidosamente) -----
# El pipeline debe DETENERSE si una llave o un join se degrada, no seguir callado.
# Un crosswalk vacio indica un fallo de parseo del diccionario y debe detener.
# Un crosswalk pequeno NO es error: los anos con menos detalle del instrumento
# (por ejemplo 2024) traen menos codigos. Corte duro bajo; lo demas, aviso.
stopifnot("Crosswalk A19b vacio (fallo de parseo del diccionario)" = nrow(crosswalk) >= 5)
if (nrow(crosswalk) < 50)
  message("Aviso: crosswalk con ", nrow(crosswalk),
          " codigos; esperable en anos con menos detalle del instrumento (p. ej. 2024).")
stopifnot("Universo con llaves (estab x mes) duplicadas" =
          !any(duplicated(universo[, .(IdEstablecimiento, Mes)])))
stopifnot("Lookup de establecimientos con codigo duplicado" =
          !any(duplicated(lookup$cod)))
match_estab <- mean(!is.na(est$TipoEstablecimientoGlosa))
if (match_estab < 0.70)
  stop(sprintf("Cruce con base maestra demasiado bajo (%.1f%%): revisa la base de establecimientos.",
               100 * match_estab))
if (match_estab < 0.95)
  warning(sprintf("Cruce con base maestra bajo lo esperado (%.1f%%).", 100 * match_estab))

# Verificacion del supuesto valor_total = Col01: Col01 debe ser la columna de TOTAL
# o conteo principal de cada seccion. En A es el total de participantes; en B y C es
# el total de actividades (B.1, C.1) o de sesiones (B.2, C.2). El conteo de
# participantes ("Total Ambos Sexos") vive en otra columna en B y C y se usa solo para
# equidad, no para el volumen del bloque.
col01_dim <- cw_col[col == "Col01", .(seccion_key, dimension)]
no_total <- col01_dim[dimension != "total"]
if (nrow(no_total) > 0)
  warning("Col01 no es columna de total en: ",
          paste(no_total$seccion_key, collapse = ", "), " (revisar valor_total).")

# ---- 6. Diccionario del dato analitico listo (se versiona) -------------------
diccionario <- data.table(
  archivo = c(rep("participacion_A19b.rds", 9), rep("participacion_largo.rds", 6),
              rep("universo_estab_mes.rds", 4)),
  variable = c("IdEstablecimiento", "Mes", "IdRegion", "IdComuna", "CodigoPrestacion",
               "valor_total", "bloque", "seccion_key", "reporto",
               "IdEstablecimiento", "Mes", "seccion_key", "dimension", "etiqueta", "valor",
               "IdEstablecimiento", "Mes", "IdRegion", "IdComuna"),
  descripcion = c(
    "Codigo del establecimiento (llave)",
    "Mes del registro (1 a 12; en preliminar, solo los meses disponibles)",
    "Region (codigo)", "Comuna (codigo)", "Codigo de prestacion REM (09xxxxxx)",
    "Valor total de la prestacion (Col01); NA = no reportado, NO es 0",
    "Bloque tematico: A (OIRS), B (participacion social), C (satisfaccion)",
    "Seccion hoja del A19b: A, B.1, B.2, C.1, C.2",
    "TRUE si la celda fue reportada (valor_total no NA)",
    "Codigo del establecimiento", "Mes", "Seccion hoja",
    "Dimension de la columna (sexo, identidad_genero, pueblos_originarios, migrantes, prais, instancia, total)",
    "Etiqueta de la categoria dentro de la dimension", "Valor (conteo)",
    "Codigo del establecimiento", "Mes", "Region (codigo)", "Comuna (codigo)"))
fwrite(diccionario, here("crosswalk", "diccionario_dato_analitico.csv"), sep = ";", bom = TRUE)
message("Validaciones OK. Diccionario del dato en crosswalk/diccionario_dato_analitico.csv")

# NOTA DE ALCANCE (universo): el universo establecimiento x mes se define con los
# establecimientos que reportan ALGO en la Serie A ese mes. Un establecimiento que
# no reporta nada en toda la Serie A no entra en el denominador. Por eso "cobertura"
# y "subregistro" se interpretan sobre los establecimientos ACTIVOS en REM, no sobre
# el total de establecimientos del pais.
