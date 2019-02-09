{-# LANGUAGE DefaultSignatures , OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables , MultiParamTypeClasses, RankNTypes , DisambiguateRecordFields , FlexibleInstances , FlexibleContexts , TypeOperators #-}

module Data.GraphqlHS.Generics.GQLRoot
    ( GQLRoot(..)
    )
where

import           Prelude                 hiding ( lookup )
import           Control.Monad
import           Data.List                      ( find )
import           Data.Data                      ( Data
                                                , Typeable
                                                , typeOf
                                                , TypeRep
                                                )
import           Data.Text                      ( Text(..)
                                                , pack
                                                )
import           Data.Map                       ( singleton
                                                , fromList
                                                , insert
                                                , lookup
                                                , union
                                                , elems
                                                )
import           GHC.Generics
import           Data.GraphqlHS.Types.Types     ( Object
                                                , GQLValue(..)
                                                , Eval(..)
                                                , MetaInfo(..)
                                                , GQLType(..)
                                                , GQLQueryRoot(..)
                                                )
import           Data.GraphqlHS.ErrorMessage    ( handleError
                                                , subfieldsNotSelected
                                                )
import           Data.GraphqlHS.Generics.GQLArgs
                                                ( GQLArgs(..) )
import           Data.GraphqlHS.Types.Introspection
                                                ( GQL__Type(..)
                                                , GQL__Field
                                                , GQL__TypeKind(..)
                                                , GQL__InputValue
                                                , GQLTypeLib
                                                , GQL__Deprication__Args
                                                , GQL__EnumValue
                                                , createType
                                                , createField
                                                , emptyLib
                                                )
import           Data.GraphqlHS.Generics.TypeRep
                                                ( Selectors(..) )
import           Data.Proxy
import           Data.GraphqlHS.Generics.GenericMap
                                                ( GenericMap(..)
                                                , getField
                                                , initMeta
                                                )
import           Data.Maybe                     ( fromMaybe )
import           Data.GraphqlHS.Schema.GQL__Schema
                                                ( initSchema
                                                , GQL__Schema
                                                )
import           Data.GraphqlHS.Generics.GQLRecord
                                                ( GQLRecord(..)
                                                , wrapAsObject
                                                )
import           Data.GraphqlHS.PreProcess      ( validateBySchema )

arrayMap :: GQLTypeLib -> [GQLTypeLib -> GQLTypeLib] -> GQLTypeLib
arrayMap lib []       = lib
arrayMap lib (f : fs) = arrayMap (f lib) fs

addToRespocne :: Eval GQLType -> Eval GQLType -> Eval GQLType
addToRespocne (Val (Obj responce)) (Val schema) =
    Val $ Obj (insert "__schema" schema responce)
addToRespocne _ schema = schema
unpackObj (Object x) = x

class GQLRoot a where

    decode :: a -> GQLQueryRoot  -> IO (Eval GQLType)
    default decode :: ( Generic a, Data a, GenericMap (Rep a) , Show a) => a -> GQLQueryRoot -> IO (Eval GQLType)
    decode rootValue gqlRoot =  case (validateBySchema schema "Query" (fragments gqlRoot) (queryBody gqlRoot)) of
        Val validGQL -> case (lookup "__schema" (unpackObj validGQL)) of
            Nothing -> responce
            Just (Object x) ->  do
                lib <-  responce
                item <- wrapAsObject (transform initMeta x (from $ initSchema $ elems $ schema))
                return (addToRespocne lib item)
            where 
                responce = wrapAsObject $ transform initMeta (unpackObj validGQL) (from rootValue)
        Fail x -> pure (Fail x)
        where
            schema = introspectRoot (Proxy :: Proxy a);
            


    introspectRoot :: Proxy a  -> GQLTypeLib
    default introspectRoot :: (Show a, Selectors (Rep a) , Typeable a) => Proxy a -> GQLTypeLib
    introspectRoot _ = do
        let typeLib = introspect (Proxy:: Proxy GQL__Schema) emptyLib
        arrayMap (insert "Query" (createType "Query" fields) typeLib) stack
               where
                   fieldTypes  = getFields (Proxy :: Proxy (Rep a))
                   stack = (map snd fieldTypes)
                   fields = map fst fieldTypes ++ [ createField "__schema" "GQL__Schema" [] ]
