assunto <- 6226
varas <- "405-6498,405-5024,405-3788,405-7,405-5758,405-2,405-6503"

tjsp::baixar_cjpg(
  assunto = assunto,
  vara = varas,
  diretorio = "cjpg"
)

resultados <- fs::dir_ls("cjpg") |>
  tjsp::tjsp_ler_cjpg()


juizes <- c(
  "WILSON LISBOA RIBEIRO",
  "MARIO SERGIO LEITE",
  "Liege Gueldini de Moraes"
)

dados_tjsp <- resultados |>
  dplyr::filter(classe == "Procedimento Comum Cível") |>
  dplyr::mutate(
    ano_processo = stringr::str_sub(processo, 10, 13),
    ano_processo = as.numeric(ano_processo)
  ) |>
  dplyr::filter(
    disponibilizacao > "2019-01-01",
    magistrado %in% juizes
  ) |>
  dplyr::select(processo, magistrado, disponibilizacao, vara, julgado)

readr::write_rds(dados_tjsp, "dados_tjsp.rds")

# vamos trabalhar com uma amostra
set.seed(1)
dados_tjsp <- readr::read_rds("dados_tjsp.rds") |>
  dplyr::mutate(antes_depois = disponibilizacao > "2022-05-01") |>
  dplyr::group_by(antes_depois, magistrado) |>
  dplyr::slice_sample(n = 100) |>
  dplyr::ungroup() |>
  dplyr::select(-antes_depois)


analisar_caso <- function(julg) {
  r <- httr::POST(
    url = "https://api.openai.com/v1/chat/completions",
    httr::add_headers(
      "Authorization" = paste("Bearer", Sys.getenv("OPENAI_API_KEY"))
    ),
    body = list(
      model = "gpt-4-turbo",
      response_format = list(type = "json_object"),
      messages = list(
        list(
          role = "system",
          content = readr::read_file("prompt.md")
        ),
        list(
          role = "user",
          content = stringr::str_sub(julg, -3000, -1)
        )
      )
    ),
    encode = "json"
  )
  r |>
    httr::content() |>
    purrr::pluck("choices", 1, "message", "content") |>
    jsonlite::fromJSON(simplifyDataFrame = TRUE) |>
    tibble::as_tibble()
}

safe <- purrr::possibly(analisar_caso, tibble::tibble())

dados_tjsp_result <- dados_tjsp |>
  dplyr::mutate(julgado = purrr::map(
    julgado, safe, .progress = TRUE
  ))

readr::write_rds(dados_tjsp_result, "dados_tjsp_result.rds")

set.seed(1)
da_did <- dados_tjsp_result |>
  dplyr::filter(purrr::map_lgl(julgado, \(x) nrow(x) > 0)) |>
  dplyr::mutate(julgado = purrr::map(
    julgado, \(x) dplyr::mutate(
      x,
      valor_danos_materiais = as.character(valor_danos_materiais)
    )
  )) |>
  tidyr::unnest(julgado) |>
  dplyr::mutate(danos_morais = danos_morais + rgamma(dplyr::n(), 15, 1/100)) |>
  dplyr::select(processo, magistrado, disponibilizacao, vara, danos_morais) |>
  dplyr::mutate(processo = abjutils::build_id(processo))

readr::write_csv(da_did, "da_did.csv")

piggyback::pb_upload("da_did.csv", repo = "c-eoe/tidydata", tag = "data", overwrite = TRUE)
