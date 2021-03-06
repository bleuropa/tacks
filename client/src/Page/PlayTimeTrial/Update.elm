module Page.PlayTimeTrial.Update exposing (..)

import Time exposing (millisecond, second)
import Time exposing (Time)
import Result exposing (Result(Ok, Err))
import Response exposing (..)
import Model.Shared exposing (..)
import Page.PlayTimeTrial.Model as Model exposing (..)
import Page.PlayTimeTrial.Decoders as Decoders
import ServerApi
import Game.Shared exposing (defaultGame, GameState)
import Game.Update as Game
import Game.Output as Output
import Game.Msg exposing (..)
import Task exposing (Task)
import WebSocket
import Http
import List.Extra as List
import Dialog


subscriptions : String -> LiveStatus -> Model -> Sub Msg
subscriptions host liveStatus model =
    case liveStatus.liveTimeTrial of
        Just liveTimeTrial ->
            Sub.batch
                [ WebSocket.listen
                    (ServerApi.timeTrialSocket host)
                    Decoders.decodeStringMsg
                , Sub.map GameMsg (Game.subscriptions model)
                , Sub.map DialogMsg (Dialog.subscriptions model.dialog)
                ]

        _ ->
            Sub.none


mount : Device -> LiveStatus -> Response Model Msg
mount device liveStatus =
    case liveStatus.liveTimeTrial of
        Just ltt ->
            Cmd.batch [ loadCourse ltt, Cmd.map GameMsg Game.mount, chooseDeviceControl device ]
                |> res initial

        Nothing ->
            res initial Cmd.none


chooseDeviceControl : Device -> Cmd Msg
chooseDeviceControl device =
    if device.control == UnknownControl then
        Task.succeed ChooseControlDialog
            |> Task.perform ShowDialog
    else
        Cmd.none


update : LiveStatus -> Player -> String -> Msg -> Model -> Response Model Msg
update liveStatus player host msg model =
    case msg of
        LoadCourse result ->
            case result of
                Ok course ->
                    Task.perform (InitGameState course) Time.now
                        |> res model

                Err e ->
                    -- TODO handle err
                    res model Cmd.none

        InitGameState course time ->
            let
                gameState =
                    defaultGame time course player

                newModel =
                    { model | gameState = Just gameState }

                startCmd =
                    Output.sendToTimeTrialServer host Output.StartRace

                ghostsCmd =
                    Maybe.map (electGhosts player) liveStatus.liveTimeTrial
                        |> Maybe.withDefault Cmd.none
            in
                res newModel (Cmd.batch [ startCmd, ghostsCmd ])

        GameMsg gameMsg ->
            Game.update player (Output.sendToTimeTrialServer host) gameMsg model
                |> mapCmd GameMsg
                |> updateGateRankings liveStatus.liveTimeTrial model

        ShowContext b ->
            res { model | showContext = b } Cmd.none

        ShowDialog kind ->
            Dialog.taggedOpen DialogMsg { model | dialogKind = Just kind }
                |> toResponse

        DialogMsg dialogMsg ->
            Dialog.taggedUpdate DialogMsg dialogMsg model
                |> toResponse

        Model.NoOp ->
            res model Cmd.none


loadCourse : LiveTimeTrial -> Cmd Msg
loadCourse liveTimeTrial =
    ServerApi.getCourse liveTimeTrial.track.id
        |> Http.send LoadCourse


maxGhosts : Int
maxGhosts =
    5


electGhosts : Player -> LiveTimeTrial -> Cmd Msg
electGhosts player { meta } =
    let
        playerIndex =
            List.findIndex (\r -> r.player.id == player.id) meta.rankings

        runs =
            case playerIndex of
                Just i ->
                    let
                        faster =
                            meta.rankings
                                |> List.take (i + 1)
                                |> List.reverse
                                |> List.take maxGhosts

                        slower =
                            meta.rankings
                                |> List.drop i
                    in
                        List.take maxGhosts (faster ++ slower)

                Nothing ->
                    meta.rankings
                        |> List.reverse
                        |> List.take maxGhosts
    in
        runs
            |> List.map (\r -> AddGhost r.runId r.player)
            |> List.map (Task.succeed >> (Task.perform identity))
            |> Cmd.batch
            |> Cmd.map GameMsg


updateGateRankings : Maybe LiveTimeTrial -> Model -> Response Model Msg -> Response Model Msg
updateGateRankings maybeLiveTimeTrial oldModel ({ model } as response) =
    case ( maybeLiveTimeTrial, oldModel.gameState, model.gameState ) of
        ( Just liveTimeTrial, Just oldGameState, Just gameState ) ->
            if oldGameState.playerState.crossedGates /= gameState.playerState.crossedGates then
                let
                    newModel =
                        { model | gateRankings = gateRankings liveTimeTrial gameState }
                in
                    { response | model = newModel }
            else
                response

        _ ->
            response


gateRankings : LiveTimeTrial -> GameState -> List GateRanking
gateRankings { timeTrial, track, meta } { playerState, course } =
    let
        gateNumber =
            List.length (course.start :: course.gates) - List.length playerState.crossedGates
    in
        List.head playerState.crossedGates
            |> Maybe.map (sortRankings meta.rankings gateNumber playerState.player)
            |> Maybe.withDefault []


sortRankings : List Ranking -> Int -> Player -> Float -> List GateRanking
sortRankings rankings gateNumber currentPlayer currentTime =
    rankings
        |> List.filterMap
            (\ranking ->
                List.getAt gateNumber ranking.gates
                    |> Maybe.map (\time -> GateRanking ranking.player time False)
            )
        |> (::) (GateRanking currentPlayer currentTime True)
        |> List.sortBy .time
