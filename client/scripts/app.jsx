
var React    = require('react');
var Router   = require('react-router');
var Bacon    = require('baconjs');
var $        = require('jquery');
var bjq      = require('bacon.jquery');
var Board    = require('./board');
var Home     = require('./home');
var PlayRace = require('./playRace');
var Api      = require('./api');

var Route         = Router.Route;
var DefaultRoute  = Router.DefaultRoute;
var NotFoundRoute = Router.NotFoundRoute;
var Routes        = Router.Routes;
var Link          = Router.Link;



var user = Bacon.Model({});
var userName = user.lens("name");

$.ajax(Api.currentUser()).done(u => {
  user.set(u);

  var App = React.createClass({

    render: function() {
      return (
        <div className="wrapper">
          {this.props.activeRouteHandler() || ""}
        </div>
        );
    }
  });

  React.renderComponent((
    <Routes location="history">
      <Route handler={App}>
        <DefaultRoute handler={Home} status={status} userName={userName} />
        <Route name="playRace" path="play/:id" handler={PlayRace} user={user} />
      </Route>
    </Routes>
    ), document.getElementById("app"));
})

