-- 01_design_fisico.sql 
-- Projeto de Banco de Dados 2026.2 — Prof. Marcos Bedo — UFF
-- Integrantes do grupo: João Vitor Dias Seigarro, Davi Mello, Lucas Surica, Gabriel Trindade, Kayo Calabria 
-- Decisões gerais:
-- * PKs numéricas GENERATED ALWAYS AS IDENTITY: índice B+-tree menor e comparação mais barata que string.
--   A antiga chave natural vira NOT NULL + UNIQUE.
-- * Chaves compostas com mais de 2 atributos foram colapsadas em chave artificial (video, comentario, doacao).
-- * FKs com ON UPDATE RESTRICT: as PKs referenciadas nunca mudam.
-- * Formato de data, e-mail e telefone é validado no front-end; no banco ficam só
--   regras de negócio estáveis (CHECK, ENUM, UNIQUE, FK).

-- ---------------------------------------------------------------------
-- TIPOS ENUM (domínios fechados definidos pelo enunciado)
-- ---------------------------------------------------------------------
CREATE TYPE tipo_canal_enum    AS ENUM ('privado', 'publico', 'misto');
CREATE TYPE status_doacao_enum AS ENUM ('recusado', 'recebido', 'lido');
-- Bandeiras: novas entram com ALTER TYPE ... ADD VALUE, sem reescrever a tabela.
CREATE TYPE bandeira_cartao_enum AS ENUM ('visa', 'mastercard', 'amex', 'elo', 'hipercard', 'diners');


-- ---------------------------------------------------------------------
-- EMPRESA
-- ---------------------------------------------------------------------
CREATE TABLE empresa(
    nro_empresa INTEGER GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(255) NOT NULL,
    -- Sem UNIQUE: empresas diferentes podem usar o mesmo nome fantasia.
    nome_fantasia VARCHAR(255) NOT NULL,

    CONSTRAINT pk_empresa PRIMARY KEY (nro_empresa),
    CONSTRAINT uq_empresa_nome UNIQUE (nome)
);


-- ---------------------------------------------------------------------
-- PLATAFORMA
-- ---------------------------------------------------------------------
CREATE TABLE plataforma(
    nro_plataforma INTEGER GENERATED ALWAYS AS IDENTITY,
    nome VARCHAR(100) NOT NULL,

    -- Atributo derivado (nº de linhas em plataforma_usuario), armazenado para evitar COUNT(*) a cada leitura.
    -- Mantido por trg_plataforma_usuario_qtd; trg_plataforma_protege_qtd bloqueia alteração manual (02_ddl_estendida.sql).
    qtd_users BIGINT NOT NULL DEFAULT 0,

    empresa_fund INTEGER NOT NULL,
    -- Duas colunas independentes: a responsável pode ser a própria fundadora ou outra empresa.
    empresa_respo INTEGER NOT NULL,
    data_fund DATE NOT NULL,

    CONSTRAINT pk_plataforma PRIMARY KEY (nro_plataforma),
    CONSTRAINT uq_plataforma_nome UNIQUE (nome),
    CONSTRAINT ck_plataforma_qtd_users CHECK (qtd_users >= 0),

    -- RESTRICT: CASCADE apagaria plataformas inteiras; SET NULL é impossível (colunas NOT NULL).
    CONSTRAINT fk_plataforma_empresa_fund FOREIGN KEY (empresa_fund)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_plataforma_empresa_respo FOREIGN KEY (empresa_respo)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- CONVERSAO (moeda)
-- ---------------------------------------------------------------------
CREATE TABLE conversao(
    -- Chave artificial no lugar de moeda (string) como PK.
    id SMALLINT GENERATED ALWAYS AS IDENTITY,
    -- UNIQUE preserva a unicidade da chave original; CHAR(3) por ser sempre ISO 4217.
    moeda CHAR(3) NOT NULL,
    nome VARCHAR(63) NOT NULL,
    -- valor_em_usd = valor_na_moeda * fator_conver. NUMERIC (nunca FLOAT) por precisão exata.
    fator_conver NUMERIC(18, 6) NOT NULL,

    CONSTRAINT pk_conversao PRIMARY KEY (id),
    CONSTRAINT uq_conversao_moeda UNIQUE (moeda),
    CONSTRAINT uq_conversao_nome UNIQUE (nome),
    CONSTRAINT ck_conversao_fator CHECK (fator_conver > 0)
);


-- ---------------------------------------------------------------------
-- PAIS
-- ---------------------------------------------------------------------
CREATE TABLE pais(
    -- O DDI já é chave natural numérica e estável: não precisa de chave artificial.
    ddi SMALLINT,
    nome VARCHAR(127) NOT NULL,
    moeda_id SMALLINT NOT NULL,

    CONSTRAINT pk_pais PRIMARY KEY (ddi),
    CONSTRAINT uq_pais_nome UNIQUE (nome),
    CONSTRAINT ck_pais_ddi CHECK (ddi > 0),

    CONSTRAINT fk_pais_conversao FOREIGN KEY (moeda_id)
        REFERENCES conversao (id) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- USUARIO
-- Streamers e membros são usuários (especialização com sobreposição no ER).
-- O streamer é o usuário que tem passaporte em streamer_pais.
-- ---------------------------------------------------------------------
CREATE TABLE usuario (
    nro_usuario BIGINT GENERATED ALWAYS AS IDENTITY,
    nick VARCHAR(63) NOT NULL,
    email VARCHAR(254) NOT NULL,
    data_nasc DATE NOT NULL,
    -- VARCHAR: tem "+", parênteses e zeros à esquerda. Nulável (opcional) e sem UNIQUE (telefone compartilhado).
    telefone VARCHAR(20),
    end_postal VARCHAR(255),
    pais_residencia SMALLINT NOT NULL,

    CONSTRAINT pk_usuario PRIMARY KEY (nro_usuario),
    CONSTRAINT uq_usuario_nick UNIQUE (nick),
    CONSTRAINT uq_usuario_email UNIQUE (email),

    -- RESTRICT: CASCADE apagaria todos os usuários do país.
    CONSTRAINT fk_usuario_pais FOREIGN KEY (pais_residencia)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- PLATAFORMA_USUARIO (conta do usuário em cada plataforma)
-- ---------------------------------------------------------------------
CREATE TABLE plataforma_usuario (
    nro_plataforma INTEGER NOT NULL,
    nro_usuario BIGINT NOT NULL,
    -- Número do usuário na plataforma (difere entre plataformas); renomeado para não confundir com nro_usuario.
    nro_conta BIGINT NOT NULL,

    CONSTRAINT pk_plataforma_usuario PRIMARY KEY (nro_plataforma, nro_usuario),
    CONSTRAINT uq_plataforma_usuario_conta UNIQUE (nro_plataforma, nro_conta),

    -- CASCADE: o vínculo não existe sem a plataforma nem sem o usuário.
    CONSTRAINT fk_pu_plataforma FOREIGN KEY (nro_plataforma)
        REFERENCES plataforma (nro_plataforma) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_pu_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- STREAMER_PAIS (passaporte do streamer)
-- ---------------------------------------------------------------------
CREATE TABLE streamer_pais (
    nro_streamer BIGINT NOT NULL,
    ddi_pais SMALLINT NOT NULL,
    -- VARCHAR: passaportes têm letras.
    nro_passaporte VARCHAR(20) NOT NULL,

    CONSTRAINT pk_streamer_pais PRIMARY KEY (nro_streamer, ddi_pais),
    -- Unicidade do par: o mesmo número pode existir em países diferentes.
    CONSTRAINT uq_streamer_pais_passaporte UNIQUE (ddi_pais, nro_passaporte),

    -- CASCADE: dados de passaporte não ficam no banco sem o usuário.
    CONSTRAINT fk_sp_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_sp_pais FOREIGN KEY (ddi_pais)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- EMPRESA_PAIS (país de origem e identificador nacional, ex.: CNPJ)
-- ---------------------------------------------------------------------
CREATE TABLE empresa_pais (
    nro_empresa INTEGER NOT NULL,
    ddi_pais SMALLINT NOT NULL,
    -- VARCHAR: cada país usa um formato, com letras e pontuação.
    id_nacional VARCHAR(50) NOT NULL,

    CONSTRAINT pk_empresa_pais PRIMARY KEY (nro_empresa, ddi_pais),
    -- Unicidade do par: o mesmo identificador pode existir em países diferentes.
    CONSTRAINT uq_empresa_pais_id_nacional UNIQUE (ddi_pais, id_nacional),

    CONSTRAINT fk_ep_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_ep_pais FOREIGN KEY (ddi_pais)
        REFERENCES pais (ddi) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- CANAL
-- ---------------------------------------------------------------------
CREATE TABLE canal (
    -- Substitui (nome, nro_plataforma). INTEGER: canais são bem menos numerosos que vídeos e comentários.
    id_canal INTEGER GENERATED ALWAYS AS IDENTITY,
    nome_canal VARCHAR(255) NOT NULL,
    tipo tipo_canal_enum NOT NULL,
    data_inicio DATE NOT NULL,
    descricao TEXT NOT NULL,

    -- Atributo derivado (soma de video.visu_total), mantido por trg_video_qtd_visualizacoes;
    -- trg_canal_protege_qtd bloqueia alteração manual (02_ddl_estendida.sql).
    qtd_visualizacoes BIGINT NOT NULL DEFAULT 0,

    nro_streamer BIGINT NOT NULL,
    nro_plataforma INTEGER NOT NULL,

    CONSTRAINT pk_canal PRIMARY KEY (id_canal),
    -- Chave natural do modelo relacional: nome único dentro da plataforma.
    CONSTRAINT uq_canal_plataforma_nome UNIQUE (nro_plataforma, nome_canal),
    CONSTRAINT ck_canal_qtd_visualizacoes CHECK (qtd_visualizacoes >= 0),

    CONSTRAINT fk_canal_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_canal_plataforma FOREIGN KEY (nro_plataforma)
        REFERENCES plataforma (nro_plataforma) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- PATROCINIO (só patrocínios vigentes, sem histórico)
-- ---------------------------------------------------------------------
CREATE TABLE patrocinio (
    nro_empresa INTEGER NOT NULL,
    id_canal INTEGER NOT NULL,
    -- Em dólares (definido no enunciado).
    valor NUMERIC(14, 2) NOT NULL,

    CONSTRAINT pk_patrocinio PRIMARY KEY (nro_empresa, id_canal),
    CONSTRAINT ck_patrocinio_valor CHECK (valor > 0),

    -- RESTRICT: nem empresa nem canal somem enquanto houver patrocínio vigente; encerrar = apagar a linha antes.
    CONSTRAINT fk_patrocinio_empresa FOREIGN KEY (nro_empresa)
        REFERENCES empresa (nro_empresa) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_patrocinio_canal FOREIGN KEY (id_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- NIVEL_CANAL (os 5 níveis de membro de cada canal)
-- ---------------------------------------------------------------------
CREATE TABLE nivel_canal (
    id_canal INTEGER NOT NULL,
    nivel SMALLINT NOT NULL,
    nome VARCHAR(50) NOT NULL,
    -- Valor mensal em dólares (assumido: o enunciado não cita moeda e os relatórios são em USD).
    valor NUMERIC(10, 2) NOT NULL,
    -- Caminho/URL do .gif: o arquivo fica em storage, não em BYTEA, para não inchar tabela e backups.
    gif VARCHAR(500) NOT NULL,

    CONSTRAINT pk_nivel_canal PRIMARY KEY (id_canal, nivel),
    CONSTRAINT uq_nivel_canal_nome UNIQUE (id_canal, nome),
    CONSTRAINT ck_nivel_canal_nivel CHECK (nivel BETWEEN 1 AND 5),
    CONSTRAINT ck_nivel_canal_valor CHECK (valor > 0),

    CONSTRAINT fk_nivel_canal_canal FOREIGN KEY (id_canal)
        REFERENCES canal (id_canal) ON DELETE CASCADE ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- INSCRICAO (membro vigente de um canal, sem histórico)
-- ---------------------------------------------------------------------
CREATE TABLE inscricao (
    id_canal INTEGER NOT NULL,
    nro_usuario BIGINT NOT NULL,
    nivel SMALLINT NOT NULL,

    -- Um usuário tem uma só inscrição vigente por canal.
    CONSTRAINT pk_inscricao PRIMARY KEY (id_canal, nro_usuario),

    CONSTRAINT fk_inscricao_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT,
    -- Também garante que o canal existe, pois o nível pertence a ele.
    CONSTRAINT fk_inscricao_nivel_canal FOREIGN KEY (id_canal, nivel)
        REFERENCES nivel_canal (id_canal, nivel) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- VIDEO
-- ---------------------------------------------------------------------
CREATE TABLE video (
    -- Substitui (nome_canal, nro_plataforma, titulo, dataH): 4 atributos viram 1.
    id_video BIGINT GENERATED ALWAYS AS IDENTITY,
    titulo VARCHAR(255) NOT NULL,
    dataH TIMESTAMP NOT NULL,
    tema VARCHAR(127) NOT NULL,
    -- Em segundos.
    duracao INTEGER NOT NULL,
    -- visu_simul e visu_total são dados medidos pela plataforma (não há tabela de sessões), então sem trigger.
    visu_simul INTEGER NOT NULL DEFAULT 0,
    visu_total BIGINT NOT NULL DEFAULT 0,
    id_canal INTEGER NOT NULL,

    CONSTRAINT pk_video PRIMARY KEY (id_video),
    -- Identificador natural; sem id_canal só poderia haver um vídeo com aquele título e horário em todo o banco.
    CONSTRAINT uq_video_canal_titulo_data UNIQUE (id_canal, titulo, dataH),
    CONSTRAINT ck_video_duracao CHECK (duracao > 0),
    CONSTRAINT ck_video_visu CHECK (visu_simul >= 0 AND visu_total >= visu_simul),

    -- RESTRICT: CASCADE apagaria o histórico de comentários e doações.
    CONSTRAINT fk_video_canal FOREIGN KEY (id_canal)
        REFERENCES canal (id_canal) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- PARTICIPA (streamers convidados de um vídeo)
-- ---------------------------------------------------------------------
CREATE TABLE participa (
    id_video BIGINT NOT NULL,
    nro_streamer BIGINT NOT NULL,

    CONSTRAINT pk_participa PRIMARY KEY (id_video, nro_streamer),

    CONSTRAINT fk_participa_video FOREIGN KEY (id_video)
        REFERENCES video (id_video) ON DELETE CASCADE ON UPDATE RESTRICT,
    CONSTRAINT fk_participa_usuario FOREIGN KEY (nro_streamer)
        REFERENCES usuario (nro_usuario) ON DELETE CASCADE ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- COMENTARIO
-- ---------------------------------------------------------------------
CREATE TABLE comentario (
    -- Substitui a chave de 6 atributos do modelo relacional.
    id_comentario BIGINT GENERATED ALWAYS AS IDENTITY,
    id_video BIGINT NOT NULL,
    -- Sequencial dentro do vídeo, gerado por trg_comentario_seq (quem insere não informa).
    seq INTEGER NOT NULL,
    nro_usuario BIGINT NOT NULL,
    texto TEXT NOT NULL,
    dataH TIMESTAMP NOT NULL,
    -- TRUE = online (durante a transmissão); FALSE = offline.
    coment_on BOOLEAN NOT NULL,

    CONSTRAINT pk_comentario PRIMARY KEY (id_comentario),
    CONSTRAINT uq_comentario_video_seq UNIQUE (id_video, seq),
    CONSTRAINT ck_comentario_seq CHECK (seq > 0),

    -- Na prática, a FK RESTRICT de doacao impede apagar vídeo cujo comentário tenha doação.
    CONSTRAINT fk_comentario_video FOREIGN KEY (id_video)
        REFERENCES video (id_video) ON DELETE CASCADE ON UPDATE RESTRICT,
    -- RESTRICT: os comentários alimentam as métricas de interação.
    CONSTRAINT fk_comentario_usuario FOREIGN KEY (nro_usuario)
        REFERENCES usuario (nro_usuario) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- DOACAO (superclasse disjunta: bitcoin, paypal, cartão, mecanismo da plataforma)
-- ---------------------------------------------------------------------
CREATE TABLE doacao (
    -- Substitui a chave de 7 atributos; as 4 subclasses passam a ter PK de 1 atributo.
    id_doacao BIGINT GENERATED ALWAYS AS IDENTITY,
    -- O comentário já identifica vídeo e usuário, que por isso não se repetem aqui.
    id_comentario BIGINT NOT NULL,
    -- Sequencial dentro do comentário (seq_pg no modelo relacional), gerado por trg_doacao_seq.
    seq_doacao INTEGER NOT NULL,
    -- Na MOEDA DO PAÍS DE RESIDÊNCIA de quem doou (usuario -> pais -> conversao);
    -- as consultas convertem para dólar com conversao.fator_conver.
    valor NUMERIC(14, 2) NOT NULL,
    status status_doacao_enum NOT NULL,

    CONSTRAINT pk_doacao PRIMARY KEY (id_doacao),
    CONSTRAINT uq_doacao_comentario_seq UNIQUE (id_comentario, seq_doacao),
    CONSTRAINT ck_doacao_valor CHECK (valor > 0),
    CONSTRAINT ck_doacao_seq CHECK (seq_doacao > 0),

    -- RESTRICT: apagar o comentário não pode apagar dinheiro recebido em silêncio.
    CONSTRAINT fk_doacao_comentario FOREIGN KEY (id_comentario)
        REFERENCES comentario (id_comentario) ON DELETE RESTRICT ON UPDATE RESTRICT
);


-- ---------------------------------------------------------------------
-- Subclasses de DOACAO: uma tabela por subclasse, com a PK da superclasse como PK e FK.
-- CASCADE: os dados específicos não existem sem a doação.
-- A disjunção (uma doação, uma só forma) é garantida por trg_*_forma_unica (02_ddl_estendida.sql).
-- ---------------------------------------------------------------------
CREATE TABLE bitcoin (
    id_doacao BIGINT NOT NULL,
    -- TxID: hash SHA-256 em hexadecimal (64 caracteres). UNIQUE: uma transação não vira duas doações.
    txid CHAR(64) NOT NULL,

    CONSTRAINT pk_bitcoin PRIMARY KEY (id_doacao),
    CONSTRAINT uq_bitcoin_txid UNIQUE (txid),
    CONSTRAINT fk_bitcoin_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE paypal (
    id_doacao BIGINT NOT NULL,
    id_paypal VARCHAR(30) NOT NULL,

    CONSTRAINT pk_paypal PRIMARY KEY (id_doacao),
    CONSTRAINT uq_paypal_id UNIQUE (id_paypal),
    CONSTRAINT fk_paypal_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE cartao_credito (
    id_doacao BIGINT NOT NULL,
    -- VARCHAR: até 19 dígitos e zeros à esquerda. Sem UNIQUE: o mesmo cartão doa várias vezes.
    -- (Num sistema real se guardaria token ou os 4 últimos dígitos, por PCI-DSS; aqui seguimos o enunciado.)
    nro_cartao VARCHAR(19) NOT NULL,
    bandeira bandeira_cartao_enum NOT NULL,
    dataH TIMESTAMP NOT NULL,

    CONSTRAINT pk_cartao_credito PRIMARY KEY (id_doacao),
    CONSTRAINT fk_cartao_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);

CREATE TABLE mecanismo_plat (
    id_doacao BIGINT NOT NULL,
    -- Sequencial por usuário e plataforma (ex.: 5º Super Chat do usuário no YouTube), gerado por trg_mecanismo_plat_seq.
    -- Usuário e plataforma não são guardados aqui: já são alcançados via comentario -> video -> canal.
    seq_plataforma INTEGER NOT NULL,

    CONSTRAINT pk_mecanismo_plat PRIMARY KEY (id_doacao),
    CONSTRAINT ck_mecanismo_plat_seq CHECK (seq_plataforma > 0),
    CONSTRAINT fk_mecanismo_doacao FOREIGN KEY (id_doacao)
        REFERENCES doacao (id_doacao) ON DELETE CASCADE ON UPDATE RESTRICT
);