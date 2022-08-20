defmodule TubuyaitaWeb.APIv1MessagesTest do
  use TubuyaitaWeb.ConnCase

  alias Tubuyaita.{Message, Crypto}

  defp insert_message(timestamp, text) do
    contents = Jason.encode!(%{timestamp: timestamp, text: text})
    {secret, public} = Crypto.generate_keypair()
    hash = Crypto.hash(contents)
    sign = Crypto.sign(hash, secret, public)
    Message.insert_message(contents, Crypto.to_hex(public), Crypto.to_hex(sign))
    hash
  end

  defp get_messages(conn) do
    conn
    |> get("/api/v1/messages")
    |> json_response(200)
  end

  defp get_messages(conn, param) do
    conn
    |> get("/api/v1/messages?#{param}")
    |> json_response(200)
  end

  test "response format", %{conn: conn} do
    insert_message(
      1_659_480_360_080,
      "bbb"
    )

    conn = conn |> get("/api/v1/messages?limit=1")

    assert conn |> get_resp_header("link") == [
             ~S'</api/v1/messages?cursor=eyJoIjoiemdKRWs3MXZtSVdXLVJKR1FNU3ZmNFN2eEc2cU9Scm00Vnk0c0VTVDM2QVc5NmliTENKakV2ZFdwWlktQ2tFRW5xLWFsTl9VVlc3dnZCOFVGdGFlYnc9PSIsInQiOjE2NTk0ODAzNjAwODAsInYiOjF9&limit=1>; rel="next"'
           ]

    res = json_response(conn, 200) |> Enum.at(0)

    assert res = %{
             "contents_hash" =>
               "zgJEk71vmIWW-RJGQMSvf4SvxG6qORrm4Vy4sEST36AW96ibLCJjEvdWpZY-CkEEnq-alN_UVW7vvB8UFtaebw==",
             "created_at" => 1_659_480_360_080,
             "public_key" => "Ge9BilXj2PFow61k7oF9bKUof-zrjx8KffpNP-kKjn0=",
             "raw_message" => "{\"text\":\"bbb\",\"timestamp\":1659480360080}"
           }

    rm = Jason.decode!(res["raw_message"])
    assert rm["text"] == "bbb"
    assert rm["timestamp"] == 1_659_480_360_080
  end

  test "get latest 1 message", %{conn: conn} do
    insert_message(
      DateTime.new!(~D[2022-08-02], ~T[22:45:40.050]) |> DateTime.to_unix(:millisecond),
      "aaa"
    )

    insert_message(
      DateTime.new!(~D[2022-08-02], ~T[22:46:00]) |> DateTime.to_unix(:millisecond),
      "bbb"
    )

    assert Jason.decode!((get_messages(conn, "limit=1") |> Enum.at(0))["raw_message"])["text"] ==
             "bbb"
  end

  test "get latest messages", %{conn: conn} do
    insert_message(
      DateTime.new!(~D[2022-08-02], ~T[22:45:40.050]) |> DateTime.to_unix(:millisecond),
      "aaa"
    )

    insert_message(
      DateTime.new!(~D[2022-08-02], ~T[22:46:00]) |> DateTime.to_unix(:millisecond),
      "bbb"
    )

    assert get_messages(conn) |> Enum.map(&Jason.decode!(&1["raw_message"])["text"]) ==
             ["bbb", "aaa"]
  end

  defp setup_three_message() do
    timeA = NaiveDateTime.new!(~D[2022-08-02], ~T[22:45:40.050])

    hashA =
      insert_message(
        timeA |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond),
        "aaa"
      )

    timeB = timeA

    hashB =
      insert_message(
        timeB |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond),
        "bbb"
      )

    timeC = NaiveDateTime.new!(~D[2022-08-02], ~T[22:46:00])

    hashC =
      insert_message(
        timeC |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix(:millisecond),
        "ccc"
      )

    [{timeA, hashA}, {timeB, hashB}, {timeC, hashC}]
  end

  test "get messages without cursor", %{conn: conn} do
    [{timeA, hashA}, {timeB, hashB}, _] = setup_three_message()
    # BのほうがAよりも先に書かれた扱いになる
    assert timeA == timeB
    assert hashB < hashA

    assert get_messages(conn) |> Enum.map(&Jason.decode!(&1["raw_message"])["text"]) == [
             "ccc",
             "aaa",
             "bbb"
           ]
  end

  test "get messages with cursor C", %{conn: conn} do
    [{timeA, hashA}, {timeB, hashB}, {timeC, hashC}] = setup_three_message()
    # BのほうがAよりも先に書かれた扱いになる
    assert timeA == timeB
    assert hashB < hashA

    cursor =
      TubuyaitaWeb.Cursor.encode(%{
        before: %{
          time: timeC,
          contents_hash: hashC
        }
      })

    assert get_messages(conn, "cursor=#{cursor}")
           |> Enum.map(&Jason.decode!(&1["raw_message"])["text"]) ==
             [
               "aaa",
               "bbb"
             ]
  end

  test "get messages with cursor A", %{conn: conn} do
    [{timeA, hashA}, {timeB, hashB}, _] = setup_three_message()
    # BのほうがAよりも先に書かれた扱いになる
    assert timeA == timeB
    assert hashB < hashA

    cursor =
      TubuyaitaWeb.Cursor.encode(%{
        before: %{
          time: timeA,
          contents_hash: hashA
        }
      })

    assert get_messages(conn, "cursor=#{cursor}")
           |> Enum.map(&Jason.decode!(&1["raw_message"])["text"]) ==
             [
               "bbb"
             ]
  end

  test "get messages with cursor B", %{conn: conn} do
    [{timeA, hashA}, {timeB, hashB}, _] = setup_three_message()
    # BのほうがAよりも先に書かれた扱いになる
    assert timeA == timeB

    assert hashB < hashA

    cursor =
      TubuyaitaWeb.Cursor.encode(%{
        before: %{
          time: timeB,
          contents_hash: hashB
        }
      })

    assert get_messages(conn, "cursor=#{cursor}")
           |> Enum.map(&Jason.decode!(&1["raw_message"])["text"]) ==
             []
  end
end
