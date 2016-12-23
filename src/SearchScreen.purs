module SearchScreen where

import Prelude
import Control.Monad.Aff (Canceler, cancel, forkAff, later', nonCanceler)
import Control.Monad.Aff.AVar (AVar, makeVar', putVar, takeVar)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (error)
import Control.Monad.Reader (ask, runReaderT)
import Control.Monad.Writer.Trans (lift)
import Data.Function.Uncurried (mkFn3)
import Data.Maybe (Maybe(Just, Nothing), maybe)
import Movie.Data (OMDBMovie, Route(ShowMovie), loadDetails, searchOMDB, unwrapMovie)
import Movie.SearchBar (searchBar)
import Movies.MovieCell (movieCell)
import React (ReactClass, ReactElement, createClass, createElement, spec)
import React.SimpleAction (Dispatcher(..), dispatchEff, getProps, getState, modifyState, stateRenderer, unsafeWithRef, withDispatcher)
import ReactNative.API (keyboardDismiss)
import ReactNative.Components.ListView (ListViewDataSource, cloneWithRows, getRowCount, listView', listViewDataSource, rowRenderer')
import ReactNative.Components.Navigator (Navigator, push)
import ReactNative.Components.ScrollView (keyboardDismissMode, scrollTo)
import ReactNative.Components.Text (text)
import ReactNative.Components.View (view, view')
import ReactNative.PropTypes (center, unsafeRef)
import ReactNative.PropTypes.Color (rgba, rgbi, white)
import ReactNative.Styles (Styles, backgroundColor, flex, height, marginLeft, marginTop, marginVertical, opacity, staticStyles, styles')
import ReactNative.Styles.Flex (alignItems)
import ReactNative.Styles.Text (color)

type MyMovie = OMDBMovie
type State eff = {
    isLoading:: Boolean
  , isLoadingTail:: Boolean
  , dataSource:: ListViewDataSource MyMovie
  , filter:: String
  , queryNumber:: Int
  , running :: Maybe (AVar (Canceler eff))
}

data Action = Search String | Select MyMovie | ScrollTop

initialState :: forall eff. State eff
initialState = {
    isLoading:false
  , running: Nothing
  , isLoadingTail:false
  , dataSource: listViewDataSource []
  , filter: ""
  , queryNumber: 0
}


searchScreen :: (Navigator Route) -> ReactElement
searchScreen navigator = createElement searchScreenClass {navigator} []

searchScreenClass :: ReactClass {navigator::Navigator Route}
searchScreenClass = createClass $ customize (spec initialState $ stateRenderer (withDispatcher eval render))
  where
    customize = _ {componentDidMount = dispatchEff $ eval $ Search "frogs" }

    render (Dispatcher d) s@{isLoading} = view sheet.container [
        searchBar {
              onSearchChange: d $ Search <<< _.nativeEvent.text
            , onFocus: d \_ -> ScrollTop
            , isLoading }
      , view sheet.separator []
      , if getRowCount s.dataSource == 0 then noMovies else listView' _ { ref= unsafeRef "listview"
          , renderSeparator=mkFn3 renderSeparator
          , renderFooter = \_ -> renderFooter
          -- , onEndReached=onEndReached
          -- , automaticallyAdjustContentInsets=false
          , keyboardDismissMode=keyboardDismissMode.onDrag
          , keyboardShouldPersistTaps= true-- "handled"
          , showsVerticalScrollIndicator=false
        } s.dataSource (rowRenderer' renderRow)
      ]
      where
        renderRow m _ _ _ = movieCell (unwrapMovie m) {onSelect: d \_ -> Select m}
        noMovies = view (styles' [sheet.container, sheet.centerText]) [ text sheet.noMoviesText movieText ]
          where movieText = if s.filter == "" then "No movies found"
                            else if s.isLoading then "" else "No results for \"" <> s.filter <> "\""

    renderSeparator s r h = let style = if h then styles' [ sheet.rowSeparator, sheet.rowSeparatorHide ] else sheet.rowSeparator
      in view' _ {key="SEP_" <> s <> r, style=style} []

    renderFooter = view sheet.scrollSpinner []

    eval ScrollTop = unsafeWithRef (scrollTo {x:0,y:0}) "listview"
    eval (Search q) = do
      {running} <- getState
      av <- maybe createAvar pure running
      lift $ takeVar av >>= flip cancel (error "Stop it")
      this <- ask
      newc <- lift $ forkAff $ later' 200 $ runReaderT doSearch this
      lift $ putVar av newc
      where
        doSearch = do
            modifyState _ {isLoading=true, filter=q}
            movies <- lift $ searchOMDB q
            modifyState \s -> s {dataSource=cloneWithRows s.dataSource movies, isLoading=false}
        createAvar = do
          a <- lift $ makeVar' nonCanceler
          modifyState _ {running = Just a}
          pure a

    eval (Select m) = do
      pure unit
      {navigator} <- getProps
      liftEff $ keyboardDismiss
      md <- lift $ loadDetails m
      lift $ liftEff $ push navigator (ShowMovie md)


sheet :: { container :: Styles
, centerText :: Styles
, noMoviesText :: Styles
, separator :: Styles
, scrollSpinner :: Styles
, rowSeparator :: Styles
, rowSeparatorHide :: Styles
}
sheet = {
    container: staticStyles [
      flex 1
    , backgroundColor white
    ]
  , centerText: staticStyles [
      alignItems center
    ]
  , noMoviesText: staticStyles [
      marginTop 80
    , color $ rgbi 0x888888
    ]
  , separator: staticStyles [
      height 1
    , backgroundColor $ rgbi 0xeeeeee
    ]
  , scrollSpinner: staticStyles [
      marginVertical 20
    ]
  , rowSeparator: staticStyles [
      backgroundColor $ rgba 0 0 0 0.1
    , height 1
    , marginLeft 4
    ]
  , rowSeparatorHide: staticStyles [
    opacity 0.0
  ]
}