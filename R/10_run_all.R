# =============================================================================
# 10_run_all.R  ·  Script maestro: ejecuta TODO el pipeline en orden
# -----------------------------------------------------------------------------
# Datos (00-03) -> motor (04-05) -> bloques (06/07/08) -> sintesis (09) ->
# manifiesto, diagnostico, A06 complementario y monitoreo multianual (10-13).
# Idempotente y parametrizable por ano con la variable de entorno REM_ANIO.
#
# Uso (consola de R):  source("R/10_run_all.R")
# Para otro ano:       Sys.setenv(REM_ANIO = "2026"); source("R/10_run_all.R")
#
# Flags opcionales (variables de entorno):
#   REM_PAR  = "1" bloques en paralelo (def) | "0" secuencial
#   REM_SENS = "1" corre la sensibilidad participativa (def) | "0" la omite
#   REM_DEP  = "0" omite dependencia en la descomposicion (def) | "1" la incluye
#   REM_FAST = "0" glmer exacto nAGQ=1 (def, cifras publicables) | "1" rapido nAGQ=0
#   REM_A06  = "1" corre el analisis complementario A06 C.1 (def) | "0" lo omite
#   REM_MON  = "1" corre el monitoreo multianual si aplica (def) | "0" lo omite
#
# Los pasos 10-13 van en tryCatch: si falta un insumo (p. ej. otros anos para el
# monitoreo), se omiten con un aviso y el pipeline no se cae.
# =============================================================================
library(here)
t0 <- Sys.time()

message("== 1/13  Descarga REM + establecimientos ==")
source(here("R", "00_descarga.R"))
message("== 2/13  Procesamiento + crosswalk A19b (bloques A/B/C) ==")
source(here("R", "01_procesamiento.R"))
message("== 3/13  Determinantes comunales (CASEN 2024) ==")
source(here("R", "02_datos_comunales.R"))
message("== 4/13  Denominador FONASA (inscritos validados) ==")
source(here("R", "03_fonasa_inscritos.R"))
message("== 5/13  Motor de analisis (funciones) ==")
source(here("R", "04_engine.R"))
message("== 6-8/13  Bloques A / B / C ==")
.runners <- c(here("R", "06_analisis_A.R"),
              here("R", "07_analisis_B.R"),
              here("R", "08_analisis_C.R"))
.root    <- here()
.envp    <- c(REM_ANIO = Sys.getenv("REM_ANIO", unset = "2025"),
              REM_SENS = Sys.getenv("REM_SENS", unset = "1"),
              REM_DEP  = Sys.getenv("REM_DEP",  unset = "0"),
              REM_FAST = Sys.getenv("REM_FAST", unset = "0"))
.correr_secuencial <- function() {
  for (rf in .runners) source(rf)
}
.paralelo_ok <- FALSE
if (Sys.getenv("REM_PAR", unset = "1") == "1") {
  .paralelo_ok <- tryCatch({
    ncores <- max(1L, min(3L, parallel::detectCores(logical = FALSE) - 1L))
    if (ncores < 2L) stop("pocos nucleos")
    message(sprintf("  -> en paralelo sobre %d nucleos", ncores))
    cl <- parallel::makeCluster(ncores)
    on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
    parallel::clusterExport(cl, c(".root", ".envp"), envir = environment())
    res <- parallel::parLapply(cl, .runners, function(rf) {
      setwd(.root)
      do.call(Sys.setenv, as.list(.envp))
      tryCatch({ source(rf); "ok" },
               error = function(e) paste0("ERROR: ", conditionMessage(e)))
    })
    parallel::stopCluster(cl)
    print(stats::setNames(unlist(res), basename(.runners)))
    all(vapply(res, identical, logical(1), "ok"))
  }, error = function(e) { message("  paralelo fallo (", conditionMessage(e),
                                   "); uso respaldo secuencial"); FALSE })
}
if (!isTRUE(.paralelo_ok)) {
  message("  -> bloques en secuencia")
  .correr_secuencial()
}
message("== 9/13  Sintesis A/B/C + indicadores de auditoria social ==")
source(here("R", "09_sintesis.R"))

message("== 10/13  Manifiesto de procedencia (huellas de los insumos) ==")
tryCatch(source(here("R", "manifiesto_datos.R")),
         error = function(e) message("  manifiesto omitido: ", conditionMessage(e)))
message("== 11/13  Diagnostico del dato ==")
tryCatch(source(here("R", "diagnostico_datos.R")),
         error = function(e) message("  diagnostico omitido: ", conditionMessage(e)))
message("== 12/13  A06 C.1 (analisis complementario salud mental) ==")
if (Sys.getenv("REM_A06", unset = "1") == "1")
  tryCatch(source(here("R", "12_a06_salud_mental.R")),
           error = function(e) message("  A06 omitido: ", conditionMessage(e)))
else message("  (omitido por REM_A06=0)")
message("== 13/13  Monitoreo multianual (si el ano es posterior a la referencia) ==")
if (Sys.getenv("REM_MON", unset = "1") == "1")
  tryCatch(source(here("R", "11_monitoreo_2026.R")),
           error = function(e) message("  monitoreo omitido: ", conditionMessage(e)))
else message("  (omitido por REM_MON=0)")

message(sprintf("\nPipeline completo en %.1f min. Productos en productos/.",
                as.numeric(difftime(Sys.time(), t0, units = "mins"))))
message("Revisa productos/<bloque>/modelo_estado.csv para ver que modelos convergieron.")
message("Luego, en la terminal:  quarto render")
