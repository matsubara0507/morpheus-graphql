{-# LANGUAGE ConstraintKinds      #-}
{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE FlexibleInstances    #-}
{-# LANGUAGE OverloadedStrings    #-}
{-# LANGUAGE RankNTypes           #-}
{-# LANGUAGE ScopedTypeVariables  #-}
{-# LANGUAGE TypeApplications     #-}
{-# LANGUAGE TypeOperators        #-}
{-# LANGUAGE UndecidableInstances #-}

module Data.Morpheus.Kind.GQLUnion
  ( encode
  , introspect
  , Constraint
  ) where

import           Data.Maybe                                 (fromMaybe)
import           Data.Morpheus.Error.Internal               (internalErrorIO)
import           Data.Morpheus.Generics.UnionRep            (UnionRep (..))
import           Data.Morpheus.Generics.UnionResolvers      (UnionResolvers (..))
import           Data.Morpheus.Kind.GQLType                 (GQLType (..))
import           Data.Morpheus.Types.Internal.AST.Selection (Selection (..), SelectionRec (..), SelectionSet)
import           Data.Morpheus.Types.Internal.Data          (DataFullType (..), DataTypeLib)
import           Data.Morpheus.Types.Internal.Validation    (ResolveIO)
import           Data.Morpheus.Types.Internal.Value         (Value (..))
import           Data.Proxy
import           Data.Text                                  (Text)
import           GHC.Generics

type Constraint a = (Generic a, GQLType a, UnionRep (Rep a), UnionResolvers (Rep a))

-- SPEC: if there is no any fragment that supports current object Type GQL returns {}
lookupSelectionByType :: Text -> [(Text, SelectionSet)] -> SelectionSet
lookupSelectionByType type' sel = fromMaybe [] $ lookup type' sel

encode :: (Generic a, UnionResolvers (Rep a)) => (Text, Selection) -> a -> ResolveIO Value
encode (key', sel@Selection {selectionRec = UnionSelection selections'}) value =
  resolver (key', sel {selectionRec = SelectionSet (lookupSelectionByType type' selections')})
  where
    (type', resolver) = currentResolver (from value)
encode _ _ = internalErrorIO "union Resolver only should recieve UnionSelection"

introspect ::
     forall a. (GQLType a, UnionRep (Rep a))
  => Proxy a
  -> DataTypeLib
  -> DataTypeLib
introspect = updateLib (const $ Union fields) stack
  where
    (fields, stack) = unzip $ possibleTypes (Proxy @(Rep a))