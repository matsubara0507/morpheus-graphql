{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoImplicitPrelude #-}

module Data.Morpheus.Types.App
  ( App (..),
    AppData (..),
    debugApp,
    mkApp,
    runApp,
    runAppWith,
  )
where

import Control.Applicative (Applicative (..))
import Control.Monad (Monad)
import qualified Data.Aeson as A
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Functor ((<$>), Functor (..))
import Data.Morpheus.Internal.Utils
  ( (<:>),
    empty,
    failure,
    prop,
  )
import Data.Morpheus.Parser
  ( parseRequestWith,
  )
import Data.Morpheus.Rendering.RenderGQL
  ( RenderGQL (..),
  )
import Data.Morpheus.Schema.Schema (internalSchema)
import Data.Morpheus.Schema.SchemaAPI (withSystemFields)
import Data.Morpheus.Types.IO
  ( GQLRequest (..),
    GQLResponse,
    MapAPI (..),
    renderResponse,
  )
import Data.Morpheus.Types.Internal.AST
  ( GQLErrors,
    Operation (..),
    Schema (..),
    Schema (..),
    Selection (..),
    SelectionContent (..),
    VALID,
    Value,
  )
import Data.Morpheus.Types.Internal.Config
  ( Config (..),
    debugConfig,
    defaultConfig,
  )
import Data.Morpheus.Types.Internal.Resolving
  ( ResolverContext (..),
    ResponseStream,
    ResultT (..),
    RootResModel,
    cleanEvents,
    resultOr,
    runRootResModel,
  )
import Data.Morpheus.Types.Internal.Stitching (Stitching (..))
import Data.Morpheus.Validation.Document.Validation (ValidateSchema (..))
import Data.Semigroup (Semigroup (..))
import Data.Text (pack)
import Prelude
  ( ($),
    (.),
    Bool (..),
    Maybe (..),
    const,
  )

mkApp :: ValidateSchema s => Schema s -> RootResModel e m -> App e m
mkApp appSchema appResolvers =
  resultOr
    FailApp
    (App . AppData appResolvers)
    (validateSchema True defaultConfig appSchema)

data App event (m :: * -> *)
  = App {app :: AppData event m VALID}
  | FailApp {appErrors :: GQLErrors}

instance RenderGQL (App e m) where
  render App {app} = render app
  render FailApp {appErrors} = pack $ LBS.unpack (A.encode appErrors)

instance Monad m => Semigroup (App e m) where
  (FailApp err1) <> (FailApp err2) = FailApp (err1 <> err2)
  FailApp {appErrors} <> App {} = FailApp appErrors
  App {} <> FailApp {appErrors} = FailApp appErrors
  (App x) <> (App y) = resultOr FailApp App (stitch x y)

data AppData event (m :: * -> *) s = AppData
  { appResolvers :: RootResModel event m,
    appSchema :: Schema s
  }

instance RenderGQL (AppData e m s) where
  render = render . appSchema

instance Monad m => Stitching (AppData e m s) where
  stitch x y =
    AppData
      <$> prop stitch appResolvers x y
      <*> prop stitch appSchema x y

runAppWith :: Monad m => App event m -> Config -> GQLRequest -> ResponseStream event m (Value VALID)
runAppWith App {app} = runAppData app
runAppWith FailApp {appErrors} = const $ const $ failure appErrors

runAppData ::
  (Monad m, ValidateSchema s) =>
  AppData event m s ->
  Config ->
  GQLRequest ->
  ResponseStream event m (Value VALID)
runAppData AppData {appSchema, appResolvers} config request = do
  validRequest <- validateReq appSchema config request
  resovers <- withSystemFields (schema validRequest) appResolvers
  runRootResModel resovers validRequest

validateReq ::
  ( Monad m,
    ValidateSchema s
  ) =>
  Schema s ->
  Config ->
  GQLRequest ->
  ResponseStream event m ResolverContext
validateReq inputSchema config request = cleanEvents $ ResultT $ pure $ do
  validSchema <- validateSchema True config inputSchema
  schema <- internalSchema <:> validSchema
  operation <- parseRequestWith config schema request
  pure $
    ResolverContext
      { schema,
        config,
        operation,
        currentTypeName = "Root",
        currentSelection =
          Selection
            { selectionName = "Root",
              selectionArguments = empty,
              selectionPosition = operationPosition operation,
              selectionAlias = Nothing,
              selectionContent = SelectionSet (operationSelection operation),
              selectionDirectives = []
            }
      }

stateless ::
  Functor m =>
  ResponseStream event m (Value VALID) ->
  m GQLResponse
stateless = fmap renderResponse . runResultT

runApp :: (MapAPI a b, Monad m) => App e m -> a -> m b
runApp app = mapAPI (stateless . runAppWith app defaultConfig)

debugApp :: (MapAPI a b, Monad m) => App e m -> a -> m b
debugApp app = mapAPI (stateless . runAppWith app debugConfig)
