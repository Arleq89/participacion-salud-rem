# Fundamentación estadística y auditoría metodológica

> Revisión concepto por concepto de la metodología estadística del proyecto de participación ciudadana en salud (REM-A19b). Para cada método se da: qué se hace, la definición precisa del concepto, por qué es la elección correcta (con literatura verificada), los supuestos y limitaciones, y un veredicto. El objetivo es que la metodología resista escrutinio: cada decisión está anclada en literatura y cada supuesto está declarado.
>
> Las referencias se verificaron contra sus fuentes en junio de 2026. La lista completa está al final.

## Resumen de veredictos

| # | Método / concepto | Uso en el proyecto | Veredicto | Referencias clave |
|---|---|---|---|---|
| 1 | Ceros estructurales vs subregistro; panel completo | Reconstruir universo establecimiento x mes; no colapsar NA a 0 | Sólido | Mullahy 1986; Feng 2021 |
| 2 | Hurdle en dos partes (barrera + intensidad) | Separar "si registra" de "cuánto registra" | Sólido | Cragg 1971; Mullahy 1986; Min y Agresti 2005 |
| 3 | Multinivel de 3 niveles (estab/comuna/región) | Descomponer la varianza del registrar | Sólido | Snijders y Bosker 2012; Merlo 2006; Austin y Merlo 2017 |
| 4 | ICC en logística (varianza latente pi²/3) | Cuantificar el efecto contextual | Sólido, con caveat | Goldstein, Browne y Rasbash 2002; Merlo 2006; Browne 2005 |
| 5 | Aproximación Laplace (nAGQ=1), no PQL/nAGQ=0 | Estimar los modelos finales | Sólido (fortaleza) | Breslow y Clayton 1993; Rodríguez y Goldman 1995; Bolker 2009 |
| 6 | Descomposición secuencial (PCV) | Cuánto explican tipo/nivel | Sólido, con caveat de reescalamiento | Merlo 2005; Mood 2010; Karlson, Holm y Breen 2012 |
| 7 | I de Moran global y LISA, contigüidad queen | Autocorrelación espacial comunal | Sólido | Moran 1950; Anselin 1995; Bivand y Wong 2018 |
| 8 | k-means sobre composición (shares) | Tipologías de participación | Aceptable, exploratorio (caveat composicional) | Aitchison 1986; Hartigan y Wong 1979 |
| 9 | Pobreza comunal por SAE (CASEN) | Covariable contextual | Sólido | Rao y Molina 2015; Casas-Cordero 2016 |
| 10 | Inferencia múltiple y nivel ecológico | Interpretación de p-valores y covariables | Declarado y acotado | Merlo 2006; Mood 2010 |

Conclusión general: la metodología es coherente con el estado del arte en análisis multinivel de datos administrativos de salud y en modelos de conteo con exceso de ceros. Los cuatro puntos que un revisor podría cuestionar (la definición del ICC en escala latente, la aproximación de verosimilitud, la comparación de varianzas entre modelos logísticos anidados y el k-means sobre composiciones) están aquí explicitados y, en tres de los cuatro, resueltos a favor de la opción más defendible.

---

## 1. Tratamiento de los ceros: panel completo, ceros estructurales y subregistro

**Qué hacemos.** Reconstruimos el panel completo de combinaciones establecimiento x mes (el "universo" de quién pudo registrar) en vez de leer solo las filas presentes, y mantenemos la distinción entre tres situaciones: valor positivo, cero explícito y ausencia de fila. No colapsamos los faltantes a cero.

**Concepto.** En datos de conteo administrativos conviven dos tipos de cero. El **cero estructural** corresponde a unidades que por diseño no pueden generar el evento (por ejemplo, un servicio de urgencia que no tiene instancias de participación), y el **cero muestral** corresponde a unidades que podrían registrar y no lo hicieron (subregistro o ausencia real de actividad). Tratarlos igual sesga cualquier estimación.

**Por qué es correcto.** La literatura de modelos modificados en el cero parte precisamente de esta distinción (Mullahy 1986; Feng 2021). Colapsar faltantes a cero introduciría ceros que no se observaron, inflando artificialmente la masa en cero y sesgando tanto la parte de barrera como la de intensidad.

**Supuestos y límite.** El dato no permite separar, dentro de un cero muestral, "no hubo actividad" de "hubo y no se registró"; esto se declara explícitamente como límite del registro administrativo y es la razón por la que el subregistro se reporta como tal y no como ausencia de participación.

**Veredicto: sólido.** La decisión de no colapsar NA a 0 y de modelar el universo completo es la correcta y está fundamentada.

---

## 2. Modelo hurdle en dos partes: barrera y intensidad

**Qué hacemos.** Modelamos el evento en dos etapas. Una **barrera** (regresión logística de efectos mixtos: ¿registra o no?) y una **intensidad** (modelo lineal mixto sobre el logaritmo del valor en los positivos: ¿cuánto, dado que registra?).

**Concepto.** El modelo *hurdle* (de barrera o de dos partes) descompone la densidad en un proceso binario que decide si se cruza el umbral y un proceso truncado en cero para la magnitud condicional. Es el marco de Cragg (1971) para variables semicontinuas y de Mullahy (1986) para conteos.

**Por qué es correcto y por qué hurdle y no zero-inflated.** Se elige hurdle, y no un modelo inflado en cero (ZIP/ZINB), porque el cero aquí significa una sola cosa, "no se registró", y no una mezcla de dos fuentes de cero (Feng 2021; Mullahy 1986). En servicios de salud, separar "si ocurre" de "cuánto" es práctica establecida para recuentos de utilización y registros administrativos (Min y Agresti 2005). La separación en dos modelos no pierde información: en el hurdle, las dos partes son independientes por construcción, de modo que estimarlas por separado es equivalente a estimarlas conjuntamente.

**Por qué dos modelos y no un objeto único.** El intento inicial de un hurdle de binomial negativa truncada en un solo objeto (glmmTMB) no convergió por la cola extrema de la distribución (máximos de miles con mediana 4), que colapsa el parámetro de dispersión y vuelve la matriz Hessiana no definida positiva. La descomposición en barrera logística e intensidad log-normal es numéricamente estable y conceptualmente equivalente. Verificar convergencia (NaN, errores estándar inflados, dispersión cercana a cero) antes de interpretar es práctica recomendada (Bolker 2009), y el pipeline la registra en `modelo_estado.csv`.

**Supuestos y límite.** La parte de intensidad asume log-normalidad de los positivos; es una aproximación razonable y trazable, alternativa a la NB truncada que no convergió. Se declara como elección por estabilidad numérica.

**Veredicto: sólido.**

---

## 3. Modelos multinivel y descomposición de la varianza

**Qué hacemos.** La barrera se modela como regresión logística con intercepto aleatorio por establecimiento y, para la pregunta territorial, con estructura anidada de tres niveles: establecimiento dentro de comuna dentro de región.

**Concepto.** Un modelo multinivel reconoce que las observaciones están agrupadas (aquí, meses dentro de establecimientos, establecimientos dentro de comunas, comunas dentro de regiones) y reparte la varianza entre esos niveles sin subestimar el error estándar que produciría ignorar la agrupación.

**Por qué es correcto.** Es el estándar para datos jerárquicos de salud (Snijders y Bosker 2012; Austin y Merlo 2017). El precedente chileno directo (García-Huidobro 2018) usa la misma jerarquía establecimiento/comuna/región sobre APS, lo que ancla la elección en el mismo ecosistema de datos.

**Supuestos y límite.** Intercepto aleatorio (no pendientes aleatorias) y normalidad de los efectos aleatorios. Son supuestos habituales; el foco del proyecto es la partición de varianza, no la predicción individual, por lo que el intercepto aleatorio es suficiente.

**Veredicto: sólido.**

---

## 4. El ICC en modelos logísticos: la varianza latente pi²/3 y el MOR como complemento

**Qué hacemos.** Reportamos el ICC (coeficiente de correlación intraclase) de la barrera, calculado fijando la varianza de nivel 1 en pi²/3.

**Concepto.** En un modelo lineal el ICC es directo, pero en uno logístico la variable de respuesta es binaria y no tiene una varianza de nivel 1 observable. El enfoque de **variable latente** supone una variable continua subyacente con distribución logística estándar, cuya varianza es pi²/3 (aproximadamente 3,29), y calcula el ICC como la proporción de varianza de nivel superior sobre el total incluyendo ese pi²/3. El ICC así definido es la medida del "efecto contextual general": qué parte de la propensión a registrar se atribuye al establecimiento (o a la comuna, o a la región).

**Por qué es correcto.** Es el método estándar y más usado para particionar varianza en modelos logísticos multinivel (Goldstein, Browne y Rasbash 2002; Merlo 2006; Browne 2005). Merlo 2006 lo presenta de forma didáctica precisamente para epidemiología social, que es nuestro contexto.

**Caveat honesto.** El ICC en escala latente es una de varias definiciones posibles. Goldstein, Browne y Rasbash (2002) describen al menos tres métodos (el de variable latente, el de linealización y el de simulación), que pueden diferir; bajo sobredispersión, Browne (2005) discute la partición de varianza con cuidado adicional. El valor pi²/3 es una convención, no una cantidad observada.

**Recomendación de blindaje.** Complementar el ICC con el **MOR (median odds ratio)** de Merlo (2006), que expresa el efecto contextual en la escala de odds ratios (más intuitiva y comparable con los OR de los efectos fijos) y no depende del supuesto pi²/3. Reportar ICC y MOR juntos es la práctica recomendada en la literatura de salud y elimina la principal objeción posible. Esta mejora es opcional y de bajo costo (se deriva de la misma varianza de establecimiento ya estimada).

**Veredicto: sólido, con el ICC latente bien fundamentado; el MOR ahora se reporta junto al ICC, lo que deja la objeción cerrada.**

---

## 5. Aproximación de verosimilitud: Laplace, no PQL ni nAGQ=0

**Qué hacemos.** Los modelos finales y publicables se ajustan con la aproximación de **Laplace** (en lme4, `nAGQ = 1`), no con la aproximación más rápida `nAGQ = 0`. El modo rápido queda disponible solo para iterar durante el desarrollo.

**Concepto.** Ajustar un GLMM requiere integrar sobre los efectos aleatorios, integral que no tiene forma cerrada en el caso logístico. Existen aproximaciones de distinta precisión: la cuasi-verosimilitud penalizada (PQL), la de Laplace y la cuadratura de Gauss-Hermite adaptativa. La PQL y aproximaciones de orden bajo son más rápidas pero sesgan a la baja las componentes de varianza cuando la respuesta es binaria y la agrupación es fuerte.

**Por qué es correcto, y por qué es una fortaleza.** Documentamos empíricamente que `nAGQ = 0` subestimaba el ICC de la barrera (por ejemplo, en OIRS, 84 por ciento frente a 94 por ciento con Laplace). Esto coincide exactamente con la literatura: Breslow y Clayton (1993) introducen la PQL y advierten su sesgo; Rodríguez y Goldman (1995) muestran mediante simulación que las componentes de varianza con respuesta binaria sufren un sesgo a la baja sustancial cuando los efectos aleatorios son grandes; Bolker (2009) recomienda Laplace o cuadratura por encima de PQL. Elegir Laplace para las cifras publicadas, y haberlo verificado contra el modo rápido, convierte un posible cuestionamiento en una decisión documentada y defendible.

**Supuestos y límite.** Laplace es a su vez una aproximación; la cuadratura adaptativa de orden alto sería aún más precisa pero no admite la estructura anidada multinivel con varios efectos aleatorios en lme4. Laplace es el mejor compromiso disponible para esta estructura y es ampliamente aceptado.

**Veredicto: sólido. Es uno de los puntos fuertes del proyecto.**

---

## 6. Descomposición secuencial de varianza (PCV) y el problema de reescalamiento

**Qué hacemos.** Estimamos modelos anidados (M0 solo establecimiento, M1 + tipo, M2 + tipo + nivel) y reportamos cuánto baja la varianza de establecimiento al añadir cada factor (el cambio proporcional de varianza, PCV).

**Concepto.** El PCV (proportional change in variance) es la reducción relativa de la varianza de un nivel al incorporar covariables, e indica qué parte de la heterogeneidad de ese nivel "explican" esas covariables (Merlo 2005).

**Caveat honesto y central.** En modelos logísticos, comparar varianzas (o coeficientes) entre modelos anidados con distintos efectos fijos no es directo, porque la varianza de la variable latente subyacente no está identificada y cambia entre especificaciones: es el **problema de reescalamiento** (Mood 2010; Karlson, Holm y Breen 2012). Al añadir tipo y nivel, la escala latente se reescala, de modo que parte del cambio en la varianza de establecimiento refleja ese reescalamiento y no solo "explicación" genuina.

**Cómo lo manejamos.** Primero, el PCV se interpreta de forma cualitativa (tipo y nivel explican la mayor parte del efecto establecimiento) y no como una cifra exacta de "varianza explicada". Segundo, la conclusión de fondo no depende del PCV: se sostiene también en la cobertura por tipo (descriptiva, sin reescalamiento) y en la probabilidad de registrar por nivel. Tercero, se declara el caveat. Para blindarlo del todo, la recomendación es aplicar el **método KHB** (Karlson, Holm y Breen 2012), que separa el cambio por reescalamiento del cambio genuino, o reportar el PCV como ilustrativo. 

**Veredicto: sólido en la conclusión, con el caveat de reescalamiento declarado y referenciado; KHB queda como mejora opcional.**

---

## 7. Autocorrelación espacial: I de Moran global y LISA

**Qué hacemos.** Calculamos el I de Moran global de la cobertura comunal y los indicadores locales (LISA) para detectar focos, con matriz de contigüidad **queen** (vecinos que comparten borde o vértice) y pesos estandarizados por fila.

**Concepto.** El **I de Moran** (Moran 1950) mide autocorrelación espacial global: si comunas vecinas tienen valores parecidos (positivo), opuestos (negativo) o aleatorios (cercano a cero). El **LISA** (Anselin 1995) descompone ese global comuna por comuna para localizar clústeres alto-alto y bajo-bajo.

**Por qué es correcto.** Son las medidas canónicas de autocorrelación espacial; la contigüidad queen y la estandarización por fila son las opciones por defecto bien establecidas (Bivand y Wong 2018, sobre la implementación en spdep). Hay precedente chileno de I de Moran comunal en salud.

**Supuestos y límite.** Algunas comunas insulares no tienen vecinos; se maneja con `zero.policy = TRUE` (se excluyen del cálculo de vecindad sin abortar). El análisis es ecológico (a nivel comunal) y está sujeto al problema de la unidad de área modificable (MAUP): los resultados podrían cambiar con otra partición territorial. La comparación exploratoria entre el Moran de la cobertura y el de los residuos tras descontar el Servicio de Salud es descriptiva; la prueba rigurosa de "red vs geografía" es el modelo multinivel con el Servicio de Salud como nivel (sección 3), que es el que da el resultado formal.

**Veredicto: sólido, con los límites ecológico y de MAUP declarados.**

---

## 8. Tipologías por k-means sobre datos composicionales

**Qué hacemos.** Agrupamos establecimientos por la **composición** de su actividad (las proporciones que dedican a cada categoría) mediante k-means con k = 4.

**Concepto.** k-means (MacQueen 1967; algoritmo de Hartigan y Wong 1979) particiona observaciones minimizando la distancia euclidiana intra-grupo. Las **proporciones que suman 1** son datos composicionales y viven en el símplex, donde la distancia euclidiana ordinaria no respeta la geometría del espacio (Aitchison 1986).

**Caveat honesto.** Aplicar k-means euclidiano directamente sobre shares es práctica común pero no es el procedimiento de referencia para datos composicionales. Lo riguroso sería transformar con una razón logarítmica (clr o ilr) antes de agrupar (Aitchison 1986). Además, k = 4 se fijó a priori y no mediante un criterio formal (codo, silueta o estadístico de brecha).

**Cómo lo manejamos.** Las tipologías se presentan como un resultado **exploratorio y descriptivo**, no inferencial: su función es ilustrar que "participar" significa cosas distintas según el tipo de establecimiento, no estimar parámetros ni contrastar hipótesis. Esa naturaleza exploratoria es la que justifica una técnica simple.

**Recomendación de blindaje.** Si las tipologías van a tener peso argumental, (1) aplicar una transformación clr antes del k-means y (2) justificar k con silueta o estadístico de brecha. Como mejora, de costo medio.

**Veredicto: reforzado. Ahora se aplica la transformación clr (Aitchison) antes del k-means y se reporta la silueta media para k=2 a 6 (`tipologias_silueta.csv`); las tipologías se mantienen como lectura exploratoria.**

---

## 9. Pobreza comunal por estimación de áreas pequeñas (SAE) como covariable

**Qué hacemos.** Usamos la tasa de pobreza comunal CASEN por estimación de áreas pequeñas (SAE) como covariable de nivel comuna.

**Concepto.** La SAE combina la encuesta CASEN con registros administrativos para producir estimaciones comunales con menor error que la encuesta directa (Rao y Molina 2015; el modelo chileno tipo Fay-Herriot en Casas-Cordero 2016).

**Por qué es correcto.** Es la fuente oficial de pobreza comunal en Chile y el método de referencia para estimación subnacional.

**Supuestos y límite.** Es una covariable ecológica (comunal): no se infiere nada a nivel individual, por lo que no incurrimos en falacia ecológica; el uso es como contexto del establecimiento. La estimación SAE tiene su propia incertidumbre, que tratamos como conocida (no propagamos su error estándar); es una simplificación habitual y conservadora respecto del efecto detectado.

**Veredicto: sólido.**

---

## 10. Inferencia múltiple y carácter ecológico

**Qué hacemos.** Reportamos varios modelos y varios p-valores por bloque.

**Discusión.** El grueso del análisis es descriptivo y de partición de varianza, no un barrido masivo de hipótesis sobre un mismo efecto, por lo que el riesgo de falsos positivos por comparaciones múltiples es limitado. La afirmación inferencial central, que la pobreza comunal predice el registro solo en satisfacción usuaria, es fuerte (p menor que 0,001) y robusta al análisis de sensibilidad (universo participativo), lo que la hace difícil de atribuir al azar. Las covariables son contextuales y se interpretan como tales.

**Veredicto: declarado y acotado.**

---

## Recomendaciones para dejar la metodología sin flancos

En orden de impacto sobre la solidez percibida:

1. **Añadir el MOR** (median odds ratio) junto al ICC en los tres bloques. Cierra la objeción sobre la escala latente y es de bajo costo (sección 4).
2. **Declarar el caveat de reescalamiento** del PCV en el artículo y, si se quiere rigor pleno, aplicar el método KHB (sección 6).
3. **Tratar las tipologías como exploratorias** de forma explícita o, si tienen peso, usar transformación clr y justificar k (sección 8).
4. **Reportar intervalos de confianza** de las componentes de varianza (por ejemplo, por bootstrap o perfil), no solo el punto, para los ICC titulares.
5. Mantener la decisión de **Laplace** y su verificación contra el modo rápido como parte explícita de los métodos: es una fortaleza que conviene mostrar.

Con (1) a (3) implementadas o declaradas, los cuatro puntos potencialmente cuestionables quedan cubiertos.

---

## Fundamentación matemática y fórmulas

Notación. Para un establecimiento $e$, en la comuna $c$ y la región $r$, en el mes $t$: $Y_{et}$ es el conteo de eventos de la sección; $\text{reporta}_{et} = \mathbb{1}(Y_{et} > 0)$ es la variable de barrera; $X$ es el vector de covariables (tipo de establecimiento, nivel de atención, pobreza comunal, mes).

### Por qué un modelo hurdle, y su forma matemática

El dato es un conteo con muchísimos ceros y una cola muy larga. Un Poisson o una regresión lineal sobre el conteo están mal especificados: no acomodan ese exceso de ceros ni la sobredispersión. El **modelo hurdle** (de barrera) lo resuelve separando la masa en el cero del proceso de los positivos. Su función de masa de probabilidad es:

$$
\Pr(Y = y) =
\begin{cases}
1 - \pi & \text{si } y = 0 \\[4pt]
\pi \, \dfrac{f(y)}{1 - f(0)} & \text{si } y \geq 1
\end{cases}
$$

donde $\pi = \Pr(Y > 0)$ es la probabilidad de cruzar el umbral (la **barrera**) y $f(\cdot)$ es la densidad de conteo de la **intensidad**, truncada en cero por el factor $1/(1-f(0))$. Esta es la formulación de Cragg (1971) para variables semicontinuas y de Mullahy (1986) para conteos.

Se elige hurdle, y no un modelo inflado en cero (ZIP/ZINB), porque aquí el cero tiene un solo origen, "no se registró", y no una mezcla de dos procesos de cero (Feng, 2021; Mullahy, 1986). En investigación de servicios de salud, separar "si ocurre" de "cuánto" es práctica establecida para recuentos de utilización y registros administrativos (Neelon et al., 2016; Min y Agresti, 2005), que es exactamente nuestro caso.

**Operacionalización en dos partes.** El hurdle de objeto único con binomial negativa truncada no converge por la cola extrema. Por la independencia de las dos partes en el hurdle, estimarlas por separado es equivalente:

Barrera (regresión logística de efectos mixtos, tres niveles):

$$
\text{logit}\big(\pi_{et}\big) = \beta_0 + X_{et}\,\beta + u^{(R)}_{r} + u^{(C)}_{c} + u^{(E)}_{e},
\qquad
u^{(R)}_r \sim N(0,\sigma^2_R),\;
u^{(C)}_c \sim N(0,\sigma^2_C),\;
u^{(E)}_e \sim N(0,\sigma^2_E)
$$

Intensidad (modelo lineal mixto sobre el log del valor en los positivos):

$$
\log\big(Y_{et} \mid Y_{et} > 0\big) = \gamma_0 + X_{et}\,\gamma + w_{e} + \varepsilon_{et},
\qquad
w_e \sim N(0,\tau^2_E),\;\;
\varepsilon_{et} \sim N(0,\sigma^2_\varepsilon)
$$

Los efectos aleatorios $u^{(E)}_e$ y $w_e$ capturan que registrar es un rasgo estable del establecimiento.

### Partición de varianza e ICC en escala latente

En el modelo logístico no hay varianza de nivel 1 observable. Bajo el enfoque de **variable latente**, se supone una variable continua subyacente con distribución logística estándar, cuya varianza es $\pi^2/3 \approx 3{,}29$. El coeficiente de correlación intraclase de un nivel es la proporción de varianza atribuible a ese nivel:

$$
\text{ICC}_{\text{establecimiento}} = \frac{\sigma^2_E}{\sigma^2_E + \sigma^2_C + \sigma^2_R + \pi^2/3}
$$

y de forma análoga para comuna y región (Goldstein, Browne y Rasbash, 2002; Merlo et al., 2006; Browne et al., 2005). Un ICC de establecimiento alto significa que la decisión de registrar es, sobre todo, un rasgo del centro.

### Median Odds Ratio (MOR)

El MOR traslada la varianza de establecimiento a la escala de odds ratios, comparable con los OR de los efectos fijos. Es el factor mediano por el que cambian las odds de registrar al comparar dos establecimientos elegidos al azar (el de mayor con el de menor propensión):

$$
\text{MOR} = \exp\!\Big(\sqrt{2\,\sigma^2_E}\;\Phi^{-1}(0{,}75)\Big) \approx \exp\!\big(0{,}9539\,\sigma_E\big),
\qquad \Phi^{-1}(0{,}75) \approx 0{,}6745
$$

$\text{MOR} = 1$ indica que el establecimiento no introduce diferencias; cuanto mayor es el MOR, más pesa "qué establecimiento es" (Merlo et al., 2006). A diferencia del ICC, no depende del supuesto $\pi^2/3$.

### Cambio proporcional de varianza (PCV)

Para medir cuánto explican tipo y nivel del efecto establecimiento, se compara la varianza de establecimiento del modelo nulo $M_0$ con la del modelo con covariables $M_k$:

$$
\text{PCV} = \frac{\sigma^2_E(M_0) - \sigma^2_E(M_k)}{\sigma^2_E(M_0)} \times 100
$$

Se interpreta de forma cualitativa por el reescalamiento de la escala latente al añadir efectos fijos (Mood, 2010; Karlson, Holm y Breen, 2012); ver la sección 6.

### Efecto de la pobreza (odds ratio)

La pobreza comunal entra estandarizada en decenas de puntos, $\text{pobreza10} = \text{pobreza}/10$. Su odds ratio es:

$$
\text{OR}_{+10pp} = \exp(\beta_{\text{pobreza10}})
$$

el cambio multiplicativo en las odds de registrar por cada 10 puntos porcentuales más de pobreza. $\text{OR} < 1$ indica que a mayor pobreza, menor probabilidad de registro.

### Autocorrelación espacial: I de Moran y LISA

El I de Moran global mide si comunas vecinas tienen valores parecidos de cobertura $x$:

$$
I = \frac{n}{\sum_{i}\sum_{j} w_{ij}} \cdot
\frac{\sum_{i}\sum_{j} w_{ij}\,(x_i - \bar{x})(x_j - \bar{x})}{\sum_{i}(x_i - \bar{x})^2}
$$

donde $w_{ij}$ es la matriz de pesos espaciales (contigüidad queen, estandarizada por fila) y $n$ el número de comunas. $I$ cercano a su valor esperado $-1/(n-1)$ indica ausencia de patrón. El indicador local (LISA) descompone ese global comuna por comuna:

$$
I_i = \frac{x_i - \bar{x}}{\sum_{k}(x_k - \bar{x})^2 / n} \sum_{j} w_{ij}\,(x_j - \bar{x})
$$

y permite localizar focos alto-alto y bajo-bajo (Moran, 1950; Anselin, 1995).

### Tipologías por k-means

Sobre las proporciones $s_e = (s_{e1}, \dots, s_{eK})$ con $\sum_k s_{ek} = 1$ (la composición de la actividad del establecimiento $e$), k-means minimiza la inercia intra-grupo:

$$
\arg\min_{\{C_1,\dots,C_g\}} \sum_{j=1}^{g} \sum_{e \in C_j} \lVert s_e - \mu_j \rVert^2
$$

con $\mu_j$ el centroide del grupo $j$. Como las proporciones viven en el símplex, la distancia euclidiana es una aproximación; el tratamiento composicional pleno usaría una transformación de razón logarítmica antes de agrupar (Aitchison, 1986). Por eso las tipologías se reportan como exploratorias (sección 8).

---

## Referencias (verificadas, junio 2026)

Modelos de conteo y exceso de ceros:

- Cragg JG (1971). Some statistical models for limited dependent variables with application to the demand for durable goods. *Econometrica* 39(5):829-844.
- Mullahy J (1986). Specification and testing of some modified count data models. *Journal of Econometrics* 33(3):341-365.
- Lambert D (1992). Zero-inflated Poisson regression, with an application to defects in manufacturing. *Technometrics* 34(1):1-14.
- Min Y, Agresti A (2005). Random effect models for repeated measures of zero-inflated count data. *Statistical Modelling* 5(1):1-19.
- Feng CX (2021). A comparison of zero-inflated and hurdle models for modeling zero-inflated count data. *Journal of Statistical Distributions and Applications* 8:8.

Modelos mixtos, estimación y bondad de ajuste:

- Bates D, Mächler M, Bolker B, Walker S (2015). Fitting linear mixed-effects models using lme4. *Journal of Statistical Software* 67(1):1-48.
- Breslow NE, Clayton DG (1993). Approximate inference in generalized linear mixed models. *Journal of the American Statistical Association* 88(421):9-25.
- Rodríguez G, Goldman N (1995). An assessment of estimation procedures for multilevel models with binary responses. *Journal of the Royal Statistical Society A* 158(1):73-89.
- Bolker BM, Brooks ME, Clark CJ, Geange SW, Poulsen JR, Stevens MHH, White JSS (2009). Generalized linear mixed models: a practical guide for ecology and evolution. *Trends in Ecology and Evolution* 24(3):127-135.
- Nakagawa S, Schielzeth H (2013). A general and simple method for obtaining R² from generalized linear mixed-effects models. *Methods in Ecology and Evolution* 4(2):133-142.

Multinivel, partición de varianza, ICC y MOR:

- Snijders TAB, Bosker RJ (2012). *Multilevel Analysis*, 2.ª ed. Sage.
- Goldstein H, Browne W, Rasbash J (2002). Partitioning variation in multilevel models. *Understanding Statistics* 1(4):223-231.
- Browne WJ, Subramanian SV, Jones K, Goldstein H (2005). Variance partitioning in multilevel logistic models that exhibit overdispersion. *Journal of the Royal Statistical Society A* 168(3):599-613.
- Merlo J, Chaix B, Yang M, Lynch J, Råstam L (2005). A brief conceptual tutorial of multilevel analysis in social epidemiology: linking the statistical concept of clustering to the idea of contextual phenomenon. *Journal of Epidemiology and Community Health* 59(6):443-449.
- Merlo J, Chaix B, Ohlsson H, Beckman A, Johnell K, Hjerpe P, Råstam L, Larsen K (2006). A brief conceptual tutorial of multilevel analysis in social epidemiology: using measures of clustering in multilevel logistic regression to investigate contextual phenomena. *Journal of Epidemiology and Community Health* 60(4):290-297.
- Austin PC, Merlo J (2017). Intermediate and advanced topics in multilevel logistic regression analysis. *Statistics in Medicine* 36(20):3257-3277.

Comparación de modelos logísticos anidados (reescalamiento):

- Mood C (2010). Logistic regression: why we cannot do what we think we can do, and what we can do about it. *European Sociological Review* 26(1):67-82.
- Karlson KB, Holm A, Breen R (2012). Comparing regression coefficients between same-sample nested models using logit and probit: a new method. *Sociological Methodology* 42(1):286-313.

Autocorrelación espacial:

- Moran PAP (1950). Notes on continuous stochastic phenomena. *Biometrika* 37(1-2):17-23.
- Anselin L (1995). Local indicators of spatial association, LISA. *Geographical Analysis* 27(2):93-115.
- Bivand RS, Wong DWS (2018). Comparing implementations of global and local indicators of spatial association. *TEST* 27(3):716-748.

Datos composicionales y agrupamiento:

- Aitchison J (1986). *The Statistical Analysis of Compositional Data*. Chapman and Hall.
- MacQueen J (1967). Some methods for classification and analysis of multivariate observations. *Proc. 5th Berkeley Symposium* 1:281-297.
- Hartigan JA, Wong MA (1979). Algorithm AS 136: a k-means clustering algorithm. *Journal of the Royal Statistical Society C* 28(1):100-108.

Estimación de áreas pequeñas y pobreza comunal:

- Rao JNK, Molina I (2015). *Small Area Estimation*, 2.ª ed. Wiley.
- Casas-Cordero Valencia C, Encina J, Corral P (2016). Poverty mapping for the Chilean comunas. En Pratesi M (ed.), *Analysis of Poverty Data by Small Area Estimation*. Wiley.

Precedente y contexto chileno:

- García-Huidobro D, Barros X, Quiroz A, Barría M, Soto G, Vargas I (2018). Modelo de atención integral en salud familiar y comunitaria en la atención primaria chilena. *Revista Panamericana de Salud Pública* 42:e160.
