﻿unit TelegAPI.Bot;

interface

uses
  TelegAPI.Types,
  System.Generics.Collections,
  System.Rtti,
  System.Classes;

Type
  TTelegaBotOnUpdate = procedure(Const Sender: TObject; Const Update: TTelegaUpdate) of Object;
  TTelegaBorOnError = procedure(Const Sender: TObject; Const Code: Integer; Const Message: String)
    of Object;

  TTelegramBot = Class(TComponent)
  private
    FToken: String;
    FOnUpdate: TTelegaBotOnUpdate;
    FIsReceiving: Boolean;
    FUploadTimeout: Integer;
    FPollingTimeout: Integer;
    FMessageOffset: Integer;
    FOnError: TTelegaBorOnError;
    /// <summary>Монитор слежки за обновлениями</summary>
    procedure SetIsReceiving(const Value: Boolean);
  protected
    /// <summary>Мастер-функция для запросов на сервак</summary>
    Function API<T>(Const Method: String; Const Params: TDictionary<String, TValue>): T;
  public

    /// <summary>A simple method for testing your bot's auth token.</summary>
    /// <returns>Returns basic information about the bot in form of a User object.</returns>
    Function getMe: TTelegaUser;
    /// <summary>Use this method to receive incoming updates using long polling. An Array of Update objects is returned.</summary>
    /// <param name="offset">Identifier of the first update to be returned. Must be greater by one than the highest among the identifiers of previously received updates. By default, updates starting with the earliest unconfirmed update are returned. An update is considered confirmed as soon as getUpdates is called with an offset higher than its update_id. The negative offset can be specified to retrieve updates starting from -offset update from the end of the updates queue. All previous updates will forgotten. </param>
    /// <param name="limit">Limits the number of updates to be retrieved. Values between 1—100 are accepted. Defaults to 100. </param>
    /// <param name="timeout">Timeout in seconds for long polling. Defaults to 0, i.e. usual short polling</param>
    Function getUpdates(Const offset: Integer = 0; Const limit: Integer = 100;
      Const timeout: Integer = 0): TArray<TTelegaUpdate>;
    Function sendTextMessage(Const chat_id: Int64; text: String;
      disableWebPagePreview: Boolean = false; replyToMessageId: Integer = 0;
      replyMarkup: TTelegaReplyMarkup = nil; Const OtherParam: TDictionary<String, TValue> = nil)
      : TTelegaMessage; overload;
    Function sendTextMessage(Const chat_id: String; text: String;
      disableWebPagePreview: Boolean = false; replyToMessageId: Integer = 0;
      replyMarkup: TTelegaReplyMarkup = nil; Const OtherParam: TDictionary<String, TValue> = nil)
      : TTelegaMessage; overload;
    constructor Create(AOwner: TComponent); overload; override;
    constructor Create(Const Token: String); overload;
  published
    { x } property UploadTimeout: Integer read FUploadTimeout write FUploadTimeout default 60000;
    { x } property PollingTimeout: Integer read FPollingTimeout write FPollingTimeout default 1000;
    property MessageOffset: Integer read FMessageOffset write FMessageOffset default 0;
    property IsReceiving: Boolean read FIsReceiving write SetIsReceiving default false;
    property Token: String read FToken write FToken;
    property OnUpdate: TTelegaBotOnUpdate read FOnUpdate write FOnUpdate;
    property OnError: TTelegaBorOnError read FOnError write FOnError;
  End;

implementation

uses
  XSuperObject,
  System.Threading,
  System.SysUtils,
  System.Net.HttpClient,
  System.Net.URLClient;

{ TTelegram }

function TTelegramBot.API<T>(const Method: String; Const Params: TDictionary<String, TValue>): T;
var
  Http: THTTPClient;
  Content: String;
  Response: TTelegaApiResponse<T>;
  uri: TURI;
  Param: TPair<String, TValue>;
begin
  Http := THTTPClient.Create;
  uri := TURI.Create('https://api.telegram.org/bot' + FToken + '/' + Method);
  try
    // Преобразовуем параметры в строку, если нужно
    if Assigned(Params) then
      for Param in Params do
      begin
        if Param.Value.IsEmpty then
          Continue;
        if Param.Value.IsType<String> then
          uri.AddParameter(Param.Key, Param.Value.AsString);
        if Param.Value.IsType<Integer> then
          uri.AddParameter(Param.Key, Param.Value.AsInteger.ToString);
      end;
    //
    Content := Http.Get(uri.ToString).ContentAsString(TEncoding.UTF8);
    if Content.Contains('502 Bad Gateway') then
    begin
      if Assigned(OnError) then
        OnError(Self, 502, 'Bad Gateway');
      Exit;
    end;

    Response := TTelegaApiResponse<T>.FromJSON(Content);
    if Not Response.Ok then
    begin
      if Assigned(OnError) then
        OnError(Self, Response.Code, Response.Message);
      Exit;
    end;
    Result := Response.ResultObject;
  finally
    Http.Free;
  end;
end;

constructor TTelegramBot.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Create(string.Empty);
end;

constructor TTelegramBot.Create(const Token: String);
begin
  FToken := Token;
  IsReceiving := false;
  UploadTimeout := 60000;
  PollingTimeout := 1000;
  MessageOffset := 0;
end;

function TTelegramBot.getMe: TTelegaUser;
begin
  Result := Self.API<TTelegaUser>('getMe', nil);
end;

function TTelegramBot.getUpdates(const offset, limit, timeout: Integer): TArray<TTelegaUpdate>;
var
  Params: TDictionary<String, TValue>;
begin
  Params := TDictionary<String, TValue>.Create;
  try
    Params.Add('offset', offset);
    Params.Add('limit', limit);
    Params.Add('timeout', timeout);
    Result := Self.API < TArray < TTelegaUpdate >> ('getUpdates', Params);
  finally
    Params.Free;
  end;
end;

function TTelegramBot.sendTextMessage(const chat_id: String; text: String;
  disableWebPagePreview: Boolean; replyToMessageId: Integer; replyMarkup: TTelegaReplyMarkup;
  const OtherParam: TDictionary<String, TValue>): TTelegaMessage;
var
  Params: TDictionary<String, TValue>;
  I: Integer;
begin
  Params := TDictionary<String, TValue>.Create;
  try
    if Assigned(OtherParam) then
      Params := OtherParam;
    Params.Add('chat_id', chat_id);
    Params.Add('text', text);
    if disableWebPagePreview then
      Params.Add('disableWebPagePreview', disableWebPagePreview);
    if replyToMessageId = 0 then
      Params.Add('replyToMessageId', replyToMessageId);
    if Assigned(replyMarkup) then
      Params.Add('replyMarkup', replyMarkup);

    Result := Self.API<TTelegaMessage>('sendMessage', Params);
  finally
    Params.Free;
  end;
end;

function TTelegramBot.sendTextMessage(const chat_id: Int64; text: String;
  disableWebPagePreview: Boolean; replyToMessageId: Integer; replyMarkup: TTelegaReplyMarkup;
  const OtherParam: TDictionary<String, TValue>): TTelegaMessage;
begin
  Result := sendTextMessage(chat_id.ToString, text, disableWebPagePreview, replyToMessageId,
    replyMarkup, OtherParam);
end;

procedure TTelegramBot.SetIsReceiving(const Value: Boolean);
var
  Task: ITask;
begin
  // Наверное надо бы синхронизацию добавить еще на события...
  FIsReceiving := Value;
  if (NOT Assigned(OnUpdate)) or (NOT FIsReceiving) then
    Exit;
  Task := TTask.Create(
    procedure
    var
      LUpdates: TArray<TTelegaUpdate>;

    Begin
      while FIsReceiving do
      Begin
        Sleep(PollingTimeout);
        LUpdates := getUpdates(MessageOffset, 100, PollingTimeout);
        TThread.Synchronize(nil,
          procedure
          var
            Update: TTelegaUpdate;
          begin
            for Update in LUpdates do
            begin
              OnUpdate(Self, Update);
              MessageOffset := Update.Id + 1;
            end;
          end);
      end;
    end);
  Task.Start;
end;

end.
