{-# LANGUAGE ConstraintKinds          #-}
{-# LANGUAGE DisambiguateRecordFields #-}
{-# LANGUAGE FlexibleContexts         #-}
{-# LANGUAGE FlexibleInstances        #-}
{-# LANGUAGE MultiParamTypeClasses    #-}
{-# LANGUAGE NamedFieldPuns           #-}
{-# LANGUAGE OverloadedStrings        #-}
{-# LANGUAGE RankNTypes               #-}
{-# LANGUAGE ScopedTypeVariables      #-}
{-# LANGUAGE TypeApplications         #-}
{-# LANGUAGE TypeFamilies             #-}
{-# LANGUAGE TypeOperators            #-}

module Data.Morpheus.Resolve.Operator
  ( RootResCon
  , fullSchema
  , encodeQuery
  , effectEncode
  ) where

import           Data.Morpheus.Resolve.Encode               (ObjectFieldResolvers (..), resolveBySelection, resolversBy)
import           Data.Morpheus.Resolve.Generics.TypeRep     (ObjectRep (..), TypeUpdater, resolveTypes)
import           Data.Morpheus.Schema.SchemaAPI             (hiddenRootFields, schemaAPI, schemaTypes)
import           Data.Morpheus.Types.Internal.AST.Selection (SelectionSet)
import           Data.Morpheus.Types.Internal.Data          (DataArguments, DataFingerprint (..), DataType (..),
                                                             DataTypeLib (..), initTypeLib)
import           Data.Morpheus.Types.Internal.Validation    (ResolveT, SchemaValidation)
import           Data.Morpheus.Types.Internal.Value         (Value (..))
import           Data.Morpheus.Types.Resolver               (EffectT (..))
import           Data.Proxy
import           Data.Text                                  (Text)
import           Data.Typeable                              (Typeable)
import           GHC.Generics

type RootResCon m a b c = (OperatorCon m a, OperatorEffectCon m b, OperatorEffectCon m c)

type OperatorCon m a = (IntroCon a, EncodeCon m a)

type OperatorEffectCon m a = (IntroCon a, EncodeCon (EffectT m Text) a)

type Encode m a = ResolveT m a -> SelectionSet -> ResolveT m Value

type EncodeCon m a = (Generic a, ObjectFieldResolvers (Rep a) m)

type BaseEncode m a
   = EncodeCon m a =>
       DataTypeLib -> Encode m a

type EffectEncode m a
   = EncodeCon (EffectT m Text) a =>
       Encode (EffectT m Text) a

encodeQuery :: Monad m => BaseEncode m a
encodeQuery types rootResolver sel =
  fmap resolversBy rootResolver >>= resolveBySelection sel . (++) (resolversBy $ schemaAPI types)

effectEncode :: Monad m => EffectEncode m a
effectEncode rootResolver sel = rootResolver >>= resolveBySelection sel . resolversBy

type IntroCon a = (Generic a, ObjectRep (Rep a) DataArguments, Typeable a)

fullSchema ::
     forall m a b c. (IntroCon a, IntroCon b, IntroCon c)
  => ResolveT m a
  -> ResolveT (EffectT m Text) b
  -> ResolveT (EffectT m Text) c
  -> SchemaValidation DataTypeLib
fullSchema queryRes mutationRes subscriptionRes =
  querySchema queryRes >>= mutationSchema mutationRes >>= subscriptionSchema subscriptionRes
  where
    querySchema _ = resolveTypes queryType (schemaTypes : types)
      where
        queryType = initTypeLib (operatorType (hiddenRootFields ++ fields) "Query")
        (fields, types) = unzip $ objectFieldTypes (Proxy @(Rep a))

mutationSchema ::
     forall a m. IntroCon a
  => m a
  -> TypeUpdater
mutationSchema _ initialType = resolveTypes mutationType types'
  where
    mutationType = initialType {mutation = maybeOperator fields "Mutation"}
    (fields, types') = unzip $ objectFieldTypes (Proxy :: Proxy (Rep a))

subscriptionSchema ::
     forall a m. IntroCon a
  => m a
  -> TypeUpdater
subscriptionSchema _ initialType = resolveTypes mutationType types'
  where
    mutationType = initialType {subscription = maybeOperator fields "Subscription"}
    (fields, types') = unzip $ objectFieldTypes (Proxy :: Proxy (Rep a))

maybeOperator :: [a] -> Text -> Maybe (Text, DataType [a])
maybeOperator []     = const Nothing
maybeOperator fields = Just . operatorType fields

operatorType :: [a] -> Text -> (Text, DataType [a])
operatorType typeData typeName =
  (typeName, DataType {typeData, typeName, typeFingerprint = SystemFingerprint typeName, typeDescription = ""})