create or replace PACKAGE BODY AMBIENTALES_PKG_MIGRA_MACROFAUNA
IS

    -- ==========================================================================
    -- Procedimiento para registrar errores
    -- ==========================================================================
    PROCEDURE registrar_log_error_ambientales (
        p_modulo        IN VARCHAR2,
        p_mensaje       IN VARCHAR2,
        p_codigo_error  IN NUMBER DEFAULT NULL
    )
    IS
    BEGIN
        -- Inserta el registro de error en la tabla logs_errores_ambientales
        INSERT INTO logs_errores_ambientales (modulo, mensaje, codigo_error, fecha_log)
        VALUES (p_modulo, p_mensaje, p_codigo_error, SYSDATE);

    EXCEPTION
        WHEN OTHERS THEN
            -- Si ocurre un error al intentar registrar el log, imprímelo
            -- No re-lanzamos para asegurar que el intento de log no cause un fallo mayor
            DBMS_OUTPUT.PUT_LINE('Error CRÍTICO al registrar log: ' || SQLERRM ||
                                 ' en modulo: ' || p_modulo ||
                                 ' mensaje: ' || p_mensaje);
    END registrar_log_error_ambientales;

    -- ==========================================================================
    -- PROCEDIMIENTOS/FUNCIONES PRIVADAS (AUXILIARES)
    -- ==========================================================================

    -- Procedimiento privado para manejar la lógica de upsert (INSERT/UPDATE) de AMBIENTALES_MACROFAUNA
    PROCEDURE p_upsert_ambientales_macrofauna (
        p_ambientales_proyecto_muestra_id IN NUMBER,
        p_ambientales_sector_id   IN NUMBER,
        p_ambientales_region_id   IN NUMBER,
        p_n_estacion              IN NUMBER,
        p_fecha_inicio            IN DATE,
        p_fecha_termino           IN DATE,
        p_anio                    IN NUMBER ,
        p_latitud                 IN VARCHAR2 ,
        p_longitud                IN VARCHAR2,
        p_estacion_del_anio       IN VARCHAR2,
        p_profundidad             IN NUMBER ,
        x_macrofauna_id           OUT NUMBER -- OUT parameter para devolver el ID insertado/existente
    )
    IS
    BEGIN
        -- Utiliza MERGE para insertar o actualizar un registro en AMBIENTALES_MACROFAUNA
        MERGE INTO AMBIENTALES_MACROFAUNA AM
        USING (SELECT
                   p_ambientales_proyecto_muestra_id AS p_proyecto_muestra_id,
                   p_ambientales_sector_id           AS p_sector_id,
                   p_ambientales_region_id           AS p_region_id,
                   p_n_estacion                      AS p_n_estacion_val,
                   p_anio                            AS p_anio_val,
                   p_estacion_del_anio               AS p_estacion_del_anio_val,
                   p_fecha_inicio                    AS p_fecha_inicio_val,
                   p_fecha_termino                   AS p_fecha_termino_val,
                   p_latitud                         AS p_latitud_val,
                   p_longitud                        AS p_longitud_val,
                   p_profundidad                     AS p_profundidad_val
               FROM DUAL) src
        ON (    AM.AMBIENTALES_PROYECTO_MUESTRA_ID = src.p_proyecto_muestra_id
              AND AM.AMBIENTALES_SECTOR_ID = src.p_sector_id
              AND AM.AMBIENTALES_REGION_ID = src.p_region_id
              AND AM.N_ESTACION = src.p_n_estacion_val
              AND AM.ANIO = src.p_anio_val
              -- Manejo de NULLs para ESTACION_DEL_ANIO en la condición de MERGE
              AND (AM.ESTACION_DEL_ANIO = src.p_estacion_del_anio_val OR (AM.ESTACION_DEL_ANIO IS NULL AND src.p_estacion_del_anio_val IS NULL))
        )
        WHEN MATCHED THEN
            UPDATE SET
                AM.FECHA_INICIO = src.p_fecha_inicio_val,
                AM.FECHA_TERMINO = src.p_fecha_termino_val,
                AM.LATITUD = src.p_latitud_val,
                AM.LONGITUD = src.p_longitud_val,
                AM.PROFUNDIDAD = src.p_profundidad_val,
                AM.FECHA_MODIFICACION = SYSDATE -- Asumiendo que esta columna existe para el control de cambios
        WHEN NOT MATCHED THEN
            INSERT (
                AMBIENTALES_MACROFAUNA_ID,
                AMBIENTALES_PROYECTO_MUESTRA_ID,
                AMBIENTALES_SECTOR_ID,
                AMBIENTALES_REGION_ID,
                N_ESTACION,
                ANIO,
                ESTACION_DEL_ANIO,
                FECHA_INICIO,
                FECHA_TERMINO,
                LATITUD,
                LONGITUD,
                PROFUNDIDAD,
                FECHA_INGRESO
            ) VALUES (
                SEQ_AMBIENTALES_MACROFAUNA.NEXTVAL, -- Obtiene el siguiente valor de la secuencia
                src.p_proyecto_muestra_id,
                src.p_sector_id,
                src.p_region_id,
                src.p_n_estacion_val,
                src.p_anio_val,
                src.p_estacion_del_anio_val,
                src.p_fecha_inicio_val,
                src.p_fecha_termino_val,
                src.p_latitud_val,
                src.p_longitud_val,
                src.p_profundidad_val,
                SYSDATE -- Fecha de ingreso actual
            );

        -- Obtener el ID que fue insertado o ya existía
        -- Esta SELECT debe usar la misma lógica de coincidencia que la cláusula ON del MERGE
        SELECT AMBIENTALES_MACROFAUNA_ID
        INTO x_macrofauna_id
        FROM AMBIENTALES_MACROFAUNA
        WHERE AMBIENTALES_PROYECTO_MUESTRA_ID = p_ambientales_proyecto_muestra_id
          AND AMBIENTALES_SECTOR_ID = p_ambientales_sector_id
          AND AMBIENTALES_REGION_ID = p_ambientales_region_id
          AND N_ESTACION = p_n_estacion
          AND ANIO = p_anio
          AND (ESTACION_DEL_ANIO = p_estacion_del_anio OR (ESTACION_DEL_ANIO IS NULL AND p_estacion_del_anio IS NULL));
          

    EXCEPTION
        WHEN OTHERS THEN
            -- Registra el error en la tabla de logs
            registrar_log_error_ambientales(
                p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_upsert_ambientales_macrofauna',
                p_mensaje       => 'Error en upsert de AMBIENTALES_MACROFAUNA: ' || SQLERRM,
                p_codigo_error  => SQLCODE
            );
            RAISE; -- Re-lanza la excepción para que sea manejada por el llamador
    END p_upsert_ambientales_macrofauna;


    -- Procedimiento privado para manejar la lógica de upsert de Detalle de MACROFAUNA
    PROCEDURE p_upsert_macrofauna_detalle (
        p_macrofauna_id IN NUMBER,
        
        p_taxa_id       IN NUMBER,
        p_medida_id     IN NUMBER,
        p_valor         IN NUMBER
    )
    IS
    BEGIN
        -- Utiliza MERGE para insertar o actualizar un registro en AMBIENTALES_MACROFAUNA_DETALLE
        MERGE INTO AMBIENTALES_MACROFAUNA_DETALLE AMD
        USING (SELECT 1 FROM DUAL)
        ON (    AMD.AMBIENTALES_MACROFAUNA_ID = p_macrofauna_id
            AND AMD.AMBIENTALES_TAXA_ID = p_taxa_id
            AND AMD.AMBIENTALES_MEDIDA_ID = p_medida_id -- Incluido en la condición ON para unicidad
        )
        WHEN MATCHED THEN
            UPDATE SET
                AMD.VALOR = p_valor,
                AMD.FECHA_MODIFICACION = SYSDATE -- Asumiendo que esta columna existe
        WHEN NOT MATCHED THEN
            INSERT (
                AMBIENTALES_MACROFAUNA_DETALLE_ID,
                AMBIENTALES_MACROFAUNA_ID,
                AMBIENTALES_TAXA_ID,
                AMBIENTALES_MEDIDA_ID, -- Incluido en el INSERT
                VALOR,
                FECHA_INGRESO
            ) VALUES (
                SEQ_AMBIENTALES_MACROFAUNA_DETALLE.NEXTVAL, -- Siguiente valor de la secuencia
                p_macrofauna_id,
                p_taxa_id,
                p_medida_id, -- Incluido en el INSERT
                p_valor,
                SYSDATE -- Fecha de ingreso actual
            );

    EXCEPTION
        WHEN OTHERS THEN
            -- Registra el error en la tabla de logs
            registrar_log_error_ambientales(
                p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_upsert_macrofauna_detalle',
                p_mensaje       => 'Error en upsert de detalle de Macrofauna: ' || SQLERRM,
                p_codigo_error  => SQLCODE
            );
            RAISE; -- Re-lanza la excepción
    END p_upsert_macrofauna_detalle;


    -- ==========================================================================
    -- Procedimiento de migración para un año específico (AUXILIAR)
    -- ==========================================================================
    PROCEDURE p_ejecutar_migracion_por_anio (
        p_anio_migrar IN NUMBER
    )
    IS
        V_AMBIENTALES_TIPO_MUESTRA_ID NUMBER;
        V_AMBIENTALES_PROYECTO_ID NUMBER;
        V_AMBIENTALES_PROYECTO_MUESTRA_ID NUMBER;
        V_AMBIENTALES_REGION_ID NUMBER;
        V_AMBIENTALES_SECTOR_ID NUMBER;
        V_AMBIENTALES_MEDIDA_ID NUMBER;
        V_AMBIENTALES_MACROFAUNA_ID NUMBER;

        v_start_time TIMESTAMP;
        v_end_time   TIMESTAMP;

        -- Define un tipo de registro completo para los datos de origen
        TYPE r_macrofauna_source_data IS RECORD (
            ID                          NUMBER,
            NOMB_PROY                   VARCHAR2(4000),
            JEFE_PROY                   VARCHAR2(4000),
            INST_PROY                   VARCHAR2(4000),
            COD_REGION                  NUMBER,
            ZONA                        VARCHAR2(4000),
            ESTACION                    NUMBER,
            ANIO                        NUMBER,
            ESTACION_DEL_ANIO           VARCHAR2(4000), -- Puede o no existir
            FECHA_INICIO                DATE,           -- Puede o no existir
            FECHA_TERMINO               DATE,           -- Puede o no existir
            LATITUD                     VARCHAR2(4000), -- Puede o no existir
            LONGITUD                    VARCHAR2(4000), -- Puede o no existir
            PROFUNDIDAD                 NUMBER,         -- Puede o no existir
            VARIABLE                    VARCHAR2(4000),
            VALOR                       NUMBER,
            TAXA_ID                     NUMBER,         -- Puede o no existir
            ESPECIE                     VARCHAR2(4000)  -- Puede o no existir, alternativa a TAXA_ID
        );
        TYPE t_macrofauna_data IS TABLE OF r_macrofauna_source_data INDEX BY PLS_INTEGER;
        l_macrofauna_data t_macrofauna_data;
        
        c_macrofauna_dynamic SYS_REFCURSOR; -- Cursor dinámico

        -- Parámetro para el tamaño del lote de BULK COLLECT y commit intermedio
        l_bulk_limit CONSTANT NUMBER := 5000; -- Ajustar según pruebas de rendimiento
        l_rows_processed NUMBER := 0;
        
        -- Variables para SQL dinámico
        l_sql_select_cols VARCHAR2(4000);
        l_table_name VARCHAR2(128);
        
        -- Flags para verificar la existencia de columnas en la tabla de origen
        l_has_fecha_inicio BOOLEAN;
        l_has_fecha_termino BOOLEAN;
        l_has_latitud BOOLEAN;
        l_has_longitud BOOLEAN;
        l_has_profundidad BOOLEAN;
        l_has_estacion_del_anio BOOLEAN;
        l_has_taxa_id BOOLEAN;
        l_has_especie BOOLEAN;

    BEGIN
        DBMS_OUTPUT.PUT_LINE('Iniciando la migración de datos de Macrofauna para el año: ' || p_anio_migrar || '...');

        -- Registrar la hora de inicio de la migración para este año
        v_start_time := SYSTIMESTAMP;
        registrar_log_error_ambientales(
            p_modulo => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
            p_mensaje => 'Inicio de la migración de macrofauna para el año ' || p_anio_migrar || '. Fecha: ' || TO_CHAR(v_start_time, 'DD-MM-YYYY HH24:MI:SS')
        );

        BEGIN
            SELECT AMBIENTALES_TIPO_MUESTRA_ID
            INTO V_AMBIENTALES_TIPO_MUESTRA_ID
            FROM AMBIENTALES_TIPO_MUESTRA
            WHERE DESCRIPCION = 'MACROFAUNA';

            DBMS_OUTPUT.PUT_LINE('Tipo de muestra "MACROFAUNA" encontrado con ID: ' || V_AMBIENTALES_TIPO_MUESTRA_ID);

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                registrar_log_error_ambientales(
                    p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
                    p_mensaje       => 'Tipo de muestra "MACROFAUNA" no encontrado en AMBIENTALES_TIPO_MUESTRA para año ' || p_anio_migrar || '.',
                    p_codigo_error  => -20004
                );
                RAISE_APPLICATION_ERROR(-20004, 'No se encontro el tipo de muestra Macrofauna: MACROFAUNA.');
            WHEN OTHERS THEN
                registrar_log_error_ambientales(
                    p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
                    p_mensaje       => 'Error inesperado al verificar tipo de muestra para año ' || p_anio_migrar || ': ' || SQLERRM,
                    p_codigo_error  => SQLCODE
                );
                RAISE;
        END;
        
        -- ======================================================================
        -- Procesamiento de datos de la tabla de origen dinámica
        -- ======================================================================
        l_table_name := 'AMBIENTALES_MACROFAUNA_' || p_anio_migrar;

        -- Verificar la existencia de columnas en la tabla de origen
        -- Usamos ALL_TAB_COLUMNS si el usuario no es el dueño de la tabla, o USER_TAB_COLUMNS si lo es.
        -- Asumo USER_TAB_COLUMNS para simplificar.
        SELECT COUNT(1) INTO l_has_fecha_inicio FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'FECHA_INICIO';
        SELECT COUNT(1) INTO l_has_fecha_termino FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'FECHA_TERMINO';
        SELECT COUNT(1) INTO l_has_latitud FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'LATITUD';
        SELECT COUNT(1) INTO l_has_longitud FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'LONGITUD';
        SELECT COUNT(1) INTO l_has_profundidad FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'PROFUNDIDAD';
        SELECT COUNT(1) INTO l_has_estacion_del_anio FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'ESTACION_DEL_ANIO';
        SELECT COUNT(1) INTO l_has_taxa_id FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'TAXA_ID';
        SELECT COUNT(1) INTO l_has_especie FROM USER_TAB_COLUMNS WHERE TABLE_NAME = UPPER(l_table_name) AND COLUMN_NAME = 'ESPECIE';


        -- Construir la cláusula SELECT dinámica
        l_sql_select_cols := 'ID, NOMB_PROY, JEFE_PROY, INST_PROY, COD_REGION, ZONA, ESTACION, ANIO, VARIABLE, VALOR';

        IF l_has_estacion_del_anio THEN l_sql_select_cols := l_sql_select_cols || ', ESTACION_DEL_ANIO'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS ESTACION_DEL_ANIO'; END IF;
        IF l_has_fecha_inicio THEN l_sql_select_cols := l_sql_select_cols || ', FECHA_INICIO'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS FECHA_INICIO'; END IF;
        IF l_has_fecha_termino THEN l_sql_select_cols := l_sql_select_cols || ', FECHA_TERMINO'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS FECHA_TERMINO'; END IF;
        IF l_has_latitud THEN l_sql_select_cols := l_sql_select_cols || ', LATITUD'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS LATITUD'; END IF;
        IF l_has_longitud THEN l_sql_select_cols := l_sql_select_cols || ', LONGITUD'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS LONGITUD'; END IF;
        IF l_has_profundidad THEN l_sql_select_cols := l_sql_select_cols || ', PROFUNDIDAD'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS PROFUNDIDAD'; END IF;
        IF l_has_taxa_id THEN l_sql_select_cols := l_sql_select_cols || ', TAXA_ID'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS TAXA_ID'; END IF;
        IF l_has_especie THEN l_sql_select_cols := l_sql_select_cols || ', ESPECIE'; ELSE l_sql_select_cols := l_sql_select_cols || ', NULL AS ESPECIE'; END IF;


        l_sql_query := 'SELECT ' || l_sql_select_cols || ' FROM ' || l_table_name || ' ORDER BY ID';

        BEGIN
            OPEN c_macrofauna_dynamic FOR l_sql_query;
        EXCEPTION
            WHEN OTHERS THEN
                -- Captura si la tabla para el año no existe
                registrar_log_error_ambientales(
                    p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
                    p_mensaje       => 'Error al abrir cursor para tabla ' || l_table_name || ': ' || SQLERRM,
                    p_codigo_error  => SQLCODE
                );
                -- No re-lanza el error aquí, simplemente salimos del procedimiento para este año
                DBMS_OUTPUT.PUT_LINE('ADVERTENCIA: No se pudo procesar el año ' || p_anio_migrar || ' (tabla ' || l_table_name || ' no encontrada o error de acceso).');
                RETURN; -- Sale del procedimiento para este año
        END;

        LOOP
            -- Bulk collect para leer los datos en lotes del cursor dinámico
            FETCH c_macrofauna_dynamic BULK COLLECT INTO l_macrofauna_data LIMIT l_bulk_limit;

            EXIT WHEN l_macrofauna_data.COUNT = 0; -- Sale del loop si no hay más datos

            -- Itera sobre cada registro en el lote
            FOR i IN 1 .. l_macrofauna_data.COUNT LOOP
                BEGIN
                    -- Asumiendo que AMBIENTALES_REVISAR_PROYECTO, AMBIENTALES_REVISAR_PROYECTO_MUESTRA, etc.
                    -- son procedimientos/funciones definidos en otro lugar y accesibles.
                    AMBIENTALES_REVISAR_PROYECTO(l_macrofauna_data(i).NOMB_PROY , NULL ,  l_macrofauna_data(i).JEFE_PROY , l_macrofauna_data(i).INST_PROY , V_AMBIENTALES_PROYECTO_ID );
                    AMBIENTALES_REVISAR_PROYECTO_MUESTRA(V_AMBIENTALES_TIPO_MUESTRA_ID , V_AMBIENTALES_PROYECTO_ID , V_AMBIENTALES_PROYECTO_MUESTRA_ID );
                    SELECT AMBIENTALES_REGION_ID INTO V_AMBIENTALES_REGION_ID FROM AMBIENTALES_REGION WHERE CODIGO_REGION = l_macrofauna_data(i).COD_REGION;
                    AMBIENTALES_REVISAR_SECTOR(V_AMBIENTALES_REGION_ID , l_macrofauna_data(i).ZONA , V_AMBIENTALES_SECTOR_ID );
                    AMBIENTALES_REVISAR_MEDIDA(l_macrofauna_data(i).VARIABLE , V_AMBIENTALES_MEDIDA_ID);
                    
                    -- Llama al procedimiento para insertar/actualizar el registro principal de macrofauna
                    p_upsert_ambientales_macrofauna(
                        p_ambientales_proyecto_muestra_id => V_AMBIENTALES_PROYECTO_MUESTRA_ID,
                        p_ambientales_sector_id   => V_AMBIENTALES_SECTOR_ID,
                        p_ambientales_region_id   => V_AMBIENTALES_REGION_ID,
                        p_n_estacion              => l_macrofauna_data(i).ESTACION,
                        p_fecha_inicio            => l_macrofauna_data(i).FECHA_INICIO,
                        p_fecha_termino           => l_macrofauna_data(i).FECHA_TERMINO,
                        p_anio                    => l_macrofauna_data(i).ANIO ,
                        p_latitud                 => l_macrofauna_data(i).LATITUD ,
                        p_longitud                => l_macrofauna_data(i).LONGITUD,
                        p_estacion_del_anio       => l_macrofauna_data(i).ESTACION_DEL_ANIO,
                        p_profundidad             => l_macrofauna_data(i).PROFUNDIDAD,
                        x_macrofauna_id           => V_AMBIENTALES_MACROFAUNA_ID
                    );

                    -- Determinar el TAXA_ID a pasar a p_upsert_macrofauna_detalle
                    DECLARE
                        v_taxa_id_to_pass NUMBER;
                    BEGIN
                        IF l_macrofauna_data(i).TAXA_ID IS NOT NULL THEN
                            v_taxa_id_to_pass := l_macrofauna_data(i).TAXA_ID;
                        ELSIF l_macrofauna_data(i).ESPECIE IS NOT NULL THEN
                            -- Asumiendo que tienes una tabla AMBIENTALES_TAXA y una columna NOMBRE_CIENTIFICO
                            -- para buscar el ID de la especie. Si no existe, se registra el error.
                            BEGIN
                                SELECT AMBIENTALES_TAXA_ID INTO v_taxa_id_to_pass
                                FROM AMBIENTALES_TAXA
                                WHERE NOMBRE_CIENTIFICO = l_macrofauna_data(i).ESPECIE;
                            EXCEPTION
                                WHEN NO_DATA_FOUND THEN
                                    registrar_log_error_ambientales(
                                        p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
                                        p_mensaje       => 'Especie no encontrada en AMBIENTALES_TAXA: ' || l_macrofauna_data(i).ESPECIE || ' para ID de origen ' || l_macrofauna_data(i).ID || ' (Año ' || p_anio_migrar || ')',
                                        p_codigo_error  => -20005
                                    );
                                    v_taxa_id_to_pass := NULL; -- Si no se encuentra, se pasa NULL
                            END;
                        ELSE
                            v_taxa_id_to_pass := NULL; -- Si ni TAXA_ID ni ESPECIE están presentes
                        END IF;

                        -- Llama al procedimiento para insertar/actualizar el detalle de macrofauna
                        p_upsert_macrofauna_detalle(
                            p_macrofauna_id =>  V_AMBIENTALES_MACROFAUNA_ID,
                            p_taxa_id       =>  v_taxa_id_to_pass, -- Usa el TAXA_ID determinado
                            p_medida_id     => V_AMBIENTALES_MEDIDA_ID, -- Usar la variable V_AMBIENTALES_MEDIDA_ID
                            p_valor         => l_macrofauna_data(i).VALOR
                        );
                    END; -- Fin del bloque DECLARE para v_taxa_id_to_pass

                    l_rows_processed := l_rows_processed + 1;

                EXCEPTION
                    WHEN OTHERS THEN
                        -- Captura errores para cada fila individual y los registra
                        registrar_log_error_ambientales(
                            p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
                            p_mensaje       => 'Error procesando ID de origen ' || l_macrofauna_data(i).ID || ' para año ' || p_anio_migrar || ': ' || SQLERRM,
                            p_codigo_error  => SQLCODE
                        );
                        -- Continúa con la siguiente fila en lugar de detener toda la migración para este año
                END;
            END LOOP;

            -- Realiza un commit intermedio después de procesar cada lote
            COMMIT;
            DBMS_OUTPUT.PUT_LINE('Lote procesado para año ' || p_anio_migrar || '. Filas migradas hasta ahora: ' || l_rows_processed);

        END LOOP;
        CLOSE c_macrofauna_dynamic;

        -- Registrar la hora de finalización de la migración exitosa para este año
        v_end_time := SYSTIMESTAMP;
        registrar_log_error_ambientales(
            p_modulo => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
            p_mensaje => 'Migración de macrofauna para año ' || p_anio_migrar || ' completada exitosamente. Total de filas procesadas: ' || l_rows_processed || '. Hora: ' || TO_CHAR(v_end_time, 'DD-MM-YYYY HH24:MI:SS')
        );

    EXCEPTION
        WHEN OTHERS THEN
            -- Captura cualquier error global que ocurra durante la migración de un año
            DBMS_OUTPUT.PUT_LINE('Error en p_ejecutar_migracion_por_anio para año ' || p_anio_migrar || ': ' || SQLERRM);
            registrar_log_error_ambientales(
                p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.p_ejecutar_migracion_por_anio',
                p_mensaje       => 'Error general durante la migración para año ' || p_anio_migrar || ': ' || SQLERRM ||
                                    CHR(10) || 'Stack: ' || DBMS_UTILITY.FORMAT_ERROR_STACK ||
                                    CHR(10) || 'Backtrace: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                p_codigo_error  => SQLCODE
            );
            RAISE; -- Re-lanza la excepción
    END p_ejecutar_migracion_por_anio;


    -- ==========================================================================
    -- Procedimiento principal para ejecutar la migración de un rango de años (PÚBLICO)
    -- ==========================================================================
    PROCEDURE ejecutar_migracion_rango_anios (
        p_anio_inicio IN NUMBER,
        p_anio_fin    IN NUMBER
    )
    IS
        v_current_year NUMBER;
        v_overall_start_time TIMESTAMP;
        v_overall_end_time   TIMESTAMP;
    BEGIN
        v_overall_start_time := SYSTIMESTAMP;
        DBMS_OUTPUT.PUT_LINE('Iniciando migración de macrofauna para el rango de años ' || p_anio_inicio || ' a ' || p_anio_fin || '...');
        registrar_log_error_ambientales(
            p_modulo => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.ejecutar_migracion_rango_anios',
            p_mensaje => 'Inicio de la migración de macrofauna para rango de años ' || p_anio_inicio || '-' || p_anio_fin || '. Hora: ' || TO_CHAR(v_overall_start_time, 'DD-MM-YYYY HH24:MI:SS')
        );

        FOR v_current_year IN p_anio_inicio .. p_anio_fin LOOP
            BEGIN
                p_ejecutar_migracion_por_anio(v_current_year);
                COMMIT; -- Asegura que los cambios de cada año se guarden
            EXCEPTION
                WHEN OTHERS THEN
                    -- Captura y registra errores para un año específico, pero permite que el proceso continúe con el siguiente año
                    DBMS_OUTPUT.PUT_LINE('Error al procesar el año ' || v_current_year || ': ' || SQLERRM);
                    registrar_log_error_ambientales(
                        p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.ejecutar_migracion_rango_anios',
                        p_mensaje       => 'Error al procesar el año ' || v_current_year || ': ' || SQLERRM,
                        p_codigo_error  => SQLCODE
                    );
                    -- No re-lanzamos aquí para que el bucle continúe con el siguiente año
            END;
        END LOOP;

        v_overall_end_time := SYSTIMESTAMP;
        DBMS_OUTPUT.PUT_LINE('Migración de macrofauna completada para el rango de años ' || p_anio_inicio || ' a ' || p_anio_fin || '.');
        registrar_log_error_ambientales(
            p_modulo => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.ejecutar_migracion_rango_anios',
            p_mensaje => 'Migración de macrofauna para rango de años ' || p_anio_inicio || '-' || p_anio_fin || ' finalizada. Hora: ' || TO_CHAR(v_overall_end_time, 'DD-MM-YYYY HH24:MI:SS')
        );

    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('Error CRÍTICO en la migración de rango de años: ' || SQLERRM);
            registrar_log_error_ambientales(
                p_modulo        => 'AMBIENTALES_PKG_MIGRA_MACROFAUNA.ejecutar_migracion_rango_anios',
                p_mensaje       => 'Error CRÍTICO en la migración de rango de años: ' || SQLERRM ||
                                    CHR(10) || 'Stack: ' || DBMS_UTILITY.FORMAT_ERROR_STACK ||
                                    CHR(10) || 'Backtrace: ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE,
                p_codigo_error  => SQLCODE
            );
            RAISE;
    END ejecutar_migracion_rango_anios;

END AMBIENTALES_PKG_MIGRA_MACROFAUNA;